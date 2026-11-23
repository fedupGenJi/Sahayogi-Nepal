# Sahayogi Nepal - Developer guide

This file keeps the setup instructions, technical overview, and implementation notes for the project. For a short introduction to Sahayogi Nepal and the team, see [README.md](README.md). For the latest API contract and migration notes, refer to [`docs/API-CONTRACT.md`](docs/API-CONTRACT.md) and [`docs/CHANGELOG.md`](docs/CHANGELOG.md).

Mobile coordination platform for community requests, donations, volunteers and emergency supplies.
Public requesters and donors submit forms without an account; volunteers are verified before they can
take work; admins approve requests, run the central inventory and review incidents.

> **Status: hackathon prototype**, not production-ready. See `docs/` for the contract, seeding guide
> and test matrix, and `docs/CHANGELOG.md` for what changed recently.

## Team

| Person | Name                         | Area                                                                                     | Folder                                              |
| ------ | ---------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 1      | Saurav Maske                 | Flutter app: public forms, volunteer UI, map screen                                      | `apps/mobile/`                                    |
| 2      | Rujan Dhamala, Aakash Thakur | Supabase backend: schema, RLS, Edge Functions, RPCs, OTP, inventory, API contract        | `supabase/`                                       |
| 3      | Utsav Subedi                 | React admin panel: review queue, inventory board, assignments, incidents, audit timeline | `apps/admin/`                                     |
| 4      | Rujan Dhamala, Aakash Thakur | Integration, QA, maps, CI, seed/reset, demo                                              | `docs/`, `scripts/`, `.github/`, `postman/` |

Person 2 owns the canonical API contract and all migrations. Person 4 owns integration readiness and demo stability.

## Tech stack

Flutter (Dart) · Supabase (Postgres + PostGIS, Auth, Storage, Realtime, Edge Functions) ·
React + Vite + TypeScript (admin) · Valhalla routing (via the `get-route` function) · Firebase Cloud Messaging (through the `send-push` function).

## Repository layout

| Path                     | What                                                                                           |
| ------------------------ | ---------------------------------------------------------------------------------------------- |
| `apps/mobile/`         | Flutter app                                                                                    |
| `apps/admin/`          | React + Vite admin web panel                                                                   |
| `supabase/migrations/` | Schema, RLS, audit log, districts, settings, RPCs. **Never edit an applied migration.**        |
| `supabase/functions/`  | Edge Functions (`submit-request`, `*-login`, `approve-volunteer`, `get-route`, ...)    |
| `supabase/seeds/`      | `nepal_districts.sql` (77 districts with polygons, idempotent)                               |
| `scripts/`             | Demo seeding and reset (`seed_demo.mjs`, `seed_extra.mjs`, `reset_demo_remote.mjs`, ...) |
| `apps/admin/set-password/` | Admin app page volunteers use to set or reset their password                              |
| `postman/`             | Postman collection and local environment                                                       |
| `docs/`                | API contract, auth API, ownership, seeding guide, test matrix, changelog                       |

## Prerequisites

- Git, Node 20+, Docker Desktop (local Supabase)
- Supabase CLI: https://supabase.com/docs/guides/cli
- Flutter 3.24+ (Dart 3.5+): https://docs.flutter.dev/get-started/install
- Deno (optional; the Supabase CLI serves functions itself)

## First-time setup (local)

```bash
./scripts/setup.sh              # Windows: scripts/setup.ps1 ; macOS: scripts/setup-mac.sh
cp .env.example .env            # fill in values (see below)
supabase start                  # local Postgres, Auth, Storage, Studio
supabase db reset               # applies migrations + supabase/seeds/nepal_districts.sql
cd scripts && npm install && cd ..
node --env-file=.env scripts/seed_demo.mjs     # demo users, inventory, requests
node --env-file=.env scripts/seed_extra.mjs    # fills every other table
```

Run the apps:

```bash
supabase functions serve --env-file supabase/functions/.env
cd apps/admin && cp .env.example .env && npm install && npm run dev
cd apps/mobile && flutter run \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon key from `supabase status`>
```

The Android emulator reaches your machine at `10.0.2.2`; the iOS simulator uses `127.0.0.1`.

### Environment variables

| File                              | Variable                                                   | Notes                                                                                                               |
| --------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `.env` (repo root, git-ignored) | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`            | Used by `scripts/*.mjs`. **Server only.** Never put the service-role key in Flutter or the admin app.       |
|                                   | `DEMO_PASSWORD`                                          | 10+ chars with upper, lower, digit and symbol. Required for remote seeding.                                         |
|                                   | `ALLOW_DEMO_SEED=yes`                                    | Safety switch: scripts refuse to touch a non-local project without it.                                              |
|                                   | `CONFIRM_PROJECT_REF`                                    | Only for `reset_demo_remote.mjs`: the `<ref>` in `https://<ref>.supabase.co`.                                 |
| `supabase/functions/.env`       | `SET_PASSWORD_URL`, `ALLOWED_ORIGIN`, `VALHALLA_URL`, `PUSH_WEBHOOK_SECRET`, `FCM_SERVICE_ACCOUNT` | Edge Function secrets. Push to the hosted project with `supabase secrets set --env-file supabase/functions/.env`. |
| `apps/admin/.env`               | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`          | Anon key only.                                                                                                      |

On Windows PowerShell, `VAR=value command` does not work. Put variables in `.env` instead.

## Hosted Supabase project

Push the schema and seed the hosted project (demo first, production later without demo users):

```bash
supabase link --project-ref <ref>
supabase db push --include-seed
node --env-file=.env scripts/seed_demo.mjs
node --env-file=.env scripts/seed_extra.mjs
```

Full steps, the rehearsal reset and troubleshooting are in [`docs/REMOTE_SEED.md`](docs/REMOTE_SEED.md).

## Demo accounts

All use `DEMO_PASSWORD`. The password is shared in the team chat, not in Git.

| Email                                        | Role                 | Categories |
| -------------------------------------------- | -------------------- | ---------- |
| `admin@demo.test`                          | admin                | none       |
| `driver1@demo.test`, `driver2@demo.test` | volunteer (driver)   | A, B       |
| `general@demo.test`                        | volunteer (manpower) | A          |
| `doctor@demo.test`                         | volunteer (doctor)   | A, C       |

Demo emails do not receive mail. Local invite and reset emails appear in Inbucket at http://127.0.0.1:54324.

## Where things stand

Done: schema and base RLS, private document bucket, volunteer application and approval flow, login /
password-reset functions, hash-chained audit log, Nepal districts with polygons, `get-route`,
`submit-request`, seed and reset scripts for local and hosted projects, and the SQL RPC layer:
approval and stock reservation, assignment and claim, delivery progress, OTP, requester tracking, map
markers, volunteer location and stats, device tokens, inventory import and moves, incidents and the audit
timeline (migrations `...000003` to `...000007`, each RPC granted explicitly).

Later migrations (through `20261123000300`, see `docs/CHANGELOG.md`) add: push notifications (`send-push`),
approval that creates the driver offers, the hub flow (admin count, admin hub codes for donation drop-off and
resource pickup, driver issue reporting, donor item edits), reserve levels with a low-stock push, kits as the only
unit, the completed-work public map and a server-side route preview (`get-offer-route`).

Still to do: the one-time push setup on each project (`docs/DEMO-SETUP.md` step 5, then run
`scripts/check_push_setup.sql`), `supabase db push` and function deploys for the newest migrations, and the app
screens that go with them (see the end of `docs/CHANGELOG.md` entries). The admin app still calls a few RPC names
that do not exist (see `docs/CHANGELOG.md`). Details: [`docs/API-CONTRACT.md`](docs/API-CONTRACT.md).

## Working together

Read `CONTRIBUTING.md` and `docs/OWNERSHIP.md`.

- UIs build against `docs/API-CONTRACT.md`; every RPC listed there as LIVE is in the migrations.
- **Schema changes only through migrations** (`supabase migration new <name>`), never in the dashboard.
- Never commit secrets. Demo data is fictional only.
- Responses always look like `{ "data": ..., "error": ... }`.
