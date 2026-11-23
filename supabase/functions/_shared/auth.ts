import { createClient } from "npm:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

export const adminClient = () =>
  createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

export const anonClient = () =>
  createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false, flowType: "implicit" },
  });

export const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/;
export const NEPAL_PHONE_RE = /^(\+977)?9[6-8][0-9]{8}$/; // same rule as submit_request in the playbook

// Same rule as config.toml (minimum_password_length = 10, lower_upper_letters_digits_symbols). Returns a message or null.
export function passwordProblem(p: string): string | null {
  if (p.length < 10) return "Password must be at least 10 characters.";
  if (p.length > 128) return "Password must be at most 128 characters.";
  if (!/[a-z]/.test(p) || !/[A-Z]/.test(p) || !/[0-9]/.test(p) || !/[^A-Za-z0-9]/.test(p)) {
    return "Password needs a lowercase letter, an uppercase letter, a number and a symbol.";
  }
  return null;
}

export async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const clientIp = (req: Request) =>
  (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || req.headers.get("cf-connecting-ip") || "unknown";

export async function readJson(req: Request): Promise<Record<string, any> | null> {
  try {
    const b = await req.json();
    return b && typeof b === "object" && !Array.isArray(b) ? b : null;
  } catch {
    return null;
  }
}

export const bearer = (req: Request) => (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();

export async function requireUser(req: Request) {
  const token = bearer(req);
  if (!token) return null;
  const { data, error } = await adminClient().auth.getUser(token);
  return error || !data.user ? null : { user: data.user, token };
}

// One profile lookup shared by every role guard. Suspended accounts never pass.
// NOTE: `role` is only 'volunteer' | 'admin'. Driver / doctor / general are CATEGORIES (A, B, C) on a volunteer.
async function activeProfile(req: Request) {
  const u = await requireUser(req);
  if (!u) return null;
  const { data: p } = await adminClient().from("profiles")
    .select("id, role, categories, account_status").eq("id", u.user.id).maybeSingle();
  return p && p.account_status === "active" ? p : null;
}

const hasCategory = (p: { role: string; categories: string[] | null }, c: "A" | "B" | "C") =>
  p.role === "volunteer" && (p.categories ?? []).includes(c);

export async function requireDriver(req: Request) {
  const p = await activeProfile(req);
  return p && hasCategory(p, "B") ? { id: p.id } : null;
}

export async function requireDoctor(req: Request) {
  const p = await activeProfile(req);
  return p && hasCategory(p, "C") ? { id: p.id } : null;
}

export async function requireAdmin(req: Request) {
  const p = await activeProfile(req);
  return p && p.role === "admin" ? { id: p.id } : null;
}

export type ThrottleKind = "login" | "reset" | "apply" | "upload" | "otp_send" | "otp_verify"| "status_check" | "form_ai";

export async function tooMany(
  sb: ReturnType<typeof adminClient>,
  o: { kind: ThrottleKind; identHash?: string; ip: string; identMax: number; ipMax: number; windowMin: number; failuresOnly?: boolean },
): Promise<boolean> {
  const since = new Date(Date.now() - o.windowMin * 60_000).toISOString();
  const count = async (col: "identifier" | "ip", val: string) => {
    let q = sb.from("auth_attempts").select("id", { count: "exact", head: true })
      .eq("kind", o.kind).eq(col, val).gte("created_at", since);
    if (o.failuresOnly) q = q.eq("success", false);
    const { count: c } = await q;
    return c ?? 0;
  };
  if (o.identHash && (await count("identifier", o.identHash)) >= o.identMax) return true;
  if (o.ip !== "unknown" && (await count("ip", o.ip)) >= o.ipMax) return true;
  return false;
}

export const recordAttempt = (sb: ReturnType<typeof adminClient>, kind: ThrottleKind, identHash: string, ip: string, success = false) =>
  sb.from("auth_attempts").insert({ kind, identifier: identHash, ip, success });

// Writes one row to the hash-chained audit log. ALWAYS go through this (it calls append_audit_log, which takes
// the chain lock before the id is assigned); a direct insert can put ids out of chain order and break verification.
// Best effort: the action it records has already happened, so a failure is logged, not returned to the caller.
export async function audit(
  sb: ReturnType<typeof adminClient>,
  a: { action: string; actorId?: string | null; entity: string; entityId?: string | null; detail?: Record<string, unknown> | null },
) {
  const { error } = await sb.rpc("append_audit_log", {
    p_action: a.action,
    p_actor_id: a.actorId ?? null,
    p_entity: a.entity,
    p_entity_id: a.entityId ?? null,
    p_detail: a.detail ?? null,
  });
  if (error) console.error(`audit log write failed (${a.action}):`, error.message);
}
