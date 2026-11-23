import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, clientIp, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const choices: Record<string, string[]> = {
  resource_request: ["Food", "Drinking Water", "Medicine", "Clothing", "Temporary Shelter"],
  donation_offer: ["Food supplies", "Drinking water", "Medicine", "Clothing", "Temporary shelter"],
  health: ["Health Worker", "Transport Manpower", "Human Manpower"],
};
const clampText = (value: unknown, max: number) =>
  typeof value === "string" ? value.trim().slice(0, max) : "";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);
  const body = await readJson(req);
  if (!body) return fail("bad_json", "Invalid JSON.");

  const formType = String(body.form_type ?? "");
  const allowed = choices[formType];
  if (!allowed) return fail("invalid_form", "This form type is not supported.");
  const message = clampText(body.message, 2000);
  if (message.length < 2) return fail("empty_message", "Describe what you need first.");

  const ip = clientIp(req);
  const sb = adminClient();
  const ipHash = await sha256(ip);
  if (await tooMany(sb, { kind: "form_ai", identHash: ipHash, ip, identMax: 12, ipMax: 30, windowMin: 60 })) {
    return fail("too_many_requests", "AI form help is temporarily limited. Try again later.", 429);
  }
  await recordAttempt(sb, "form_ai", ipHash, ip);

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return fail("assistant_unavailable", "AI form help is not configured yet.", 503);

  const formDefinition = formType === "health"
    ? { fields: ["requester_name", "requester_phone", "affected_people", "assistance_type", "volunteers_needed"], choices: allowed }
    : { fields: ["requester_name", "requester_phone", ...(formType === "resource_request" ? ["affected_people"] : []), "items"], choices: allowed };
  const systemPrompt = `You help fill a fixed disaster-relief mobile form. The form type is ${formType}. Return only a JSON object with keys from this exact field list: ${formDefinition.fields.join(", ")}. Never invent information. Preserve names as supplied, including Nepali script or mixed language. Normalize phone digits to ASCII digits while preserving an optional +977 prefix. Return category/type values only from this exact list: ${allowed.join(" | ")}. Convert quantities and people counts written with Nepali or English numerals into positive integers. Leave unknown text fields as empty strings; use null for an unknown count/type. Do not infer or return location, urgency, notes, instructions, extra fields, or form layout. If multiple items are explicitly described, return them as items; otherwise at most one item. Each item must have only category and quantity.`;
  const userPrompt = `User's description (may be English, Nepali, or mixed):\n${message}\n\nAllowed fields and choices:\n${JSON.stringify(formDefinition)}`;
  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("FORM_ASSISTANT_MODEL") ?? "gpt-4o-mini",
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }],
      }),
      signal: AbortSignal.timeout(20000),
    });
    if (!response.ok) {
      console.error("assist-form provider status:", response.status);
      return fail("assistant_failed", "Could not prepare suggestions. Please try again.", 502);
    }
    const completion = await response.json();
    const raw = JSON.parse(completion?.choices?.[0]?.message?.content ?? "{}");
    const result: Record<string, unknown> = {
      requester_name: clampText(raw.requester_name, 120),
      requester_phone: clampText(raw.requester_phone, 32),
    };
    if (formType === "health") {
      result.affected_people = Number.isInteger(raw.affected_people) && raw.affected_people > 0 && raw.affected_people <= 100000 ? raw.affected_people : null;
      result.assistance_type = allowed.includes(raw.assistance_type) ? raw.assistance_type : null;
      result.volunteers_needed = Number.isInteger(raw.volunteers_needed) && raw.volunteers_needed > 0 && raw.volunteers_needed <= 100 ? raw.volunteers_needed : null;
    } else {
      if (formType === "resource_request") {
        result.affected_people = Number.isInteger(raw.affected_people) && raw.affected_people > 0 && raw.affected_people <= 100000 ? raw.affected_people : null;
      }
      result.items = (Array.isArray(raw.items) ? raw.items : []).slice(0, 20).flatMap((item: any) => {
        const category = allowed.includes(item?.category) ? item.category : null;
        const quantity = Number.isInteger(item?.quantity) && item.quantity > 0 && item.quantity <= 1000000 ? item.quantity : null;
        return category && quantity ? [{ category, quantity }] : [];
      });
    }
    return ok({ form_type: formType, suggestions: result });
  } catch (error) {
    console.error("assist-form failed:", error instanceof Error ? error.message : "unknown error");
    return fail("assistant_failed", "Could not prepare suggestions. Please try again.", 502);
  }
});
