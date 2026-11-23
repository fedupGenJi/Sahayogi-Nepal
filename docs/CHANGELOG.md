
# Contract and backend changelog

Newest first. Anything that changes a payload, table, function or seed behaviour gets a line here.

## 2026-11-23 (mobile auth, request history and transfer handoffs, contract v1.7)
- Mobile auth-aware navigation, profile prefill and volunteer stats; saved request history clears between anonymous and volunteer sessions.
- Added owner-scoped volunteer request history and requester/driver OTP, quantity and issue-report flows; admin assignment details can count donations and issue hub OTPs.
- Increased the volunteer application IP limit to 500 per 24 hours; the per-phone limit remains 3.

## 2026-11-23 (hub pickup code and refusal for resource requests, contract v1.6)

- **Migration `20261123000300_hub_pickup_otp.sql`:** `admin_issue_otp` now picks the purpose from the job: a `delivery` job that is `accepted` or `en_route_to_pickup` gets a `hub_pickup` code (6 digits, hashed, 15 minutes, 5 attempts, 10 per hour). The driver enters it in `driver_verify_otp` (purpose `hub_pickup`) and only then is the job `picked_up`. `update_assignment_state` no longer allows `delivery` -> `picked_up` (`otp_required`). Stock stays reserved until the requester's delivery code.
- **`driver_report_issue`** also works for a `delivery` job before `hub_pickup` (incident types `hub_pickup_refused`, `hub_items_mismatch`). The job is released with that driver excluded and the request goes back to `awaiting_assignment`. **Decision (c):** the reserved stock is kept, because another driver still has to deliver it; the admin can decline the request from the incident to release it.
- **Tested** on a scratch PostgreSQL with a reduced schema (no PostGIS); not on the Supabase project.
- **Deploy:** `supabase db push`, then `supabase functions deploy admin-api volunteer-api`. **Apps:** driver app needs a `hub_pickup` code entry step and the report-issue screen for delivery jobs; admin app shows the code once.

## 2026-11-23 (hub drop-off code)

- **Migration `20261123000200_hub_dropoff_otp.sql`:** `otp_challenges.purpose` allows `hub_dropoff`. New RPC `admin_issue_otp(p_id)` (edge route `admin-api/assignments/issue-otp`): after the hub count the admin gets a 6-digit code (hashed, 15 minutes, 5 attempts, 10 per hour, shown once) and reads it to the driver. `driver_verify_otp` (purpose `hub_dropoff`) then sets the job `delivered` and the donation request `fulfilled`. The driver can no longer mark a pickup job delivered (`update_assignment_state` answers `otp_required`). Before the count the admin gets `not_received`. Donations picked up before the hub count existed keep their lots and count as counted.

## 2026-11-23 (hub count, stock from the count)

- **Migration `20261123000100_hub_receive_count.sql`:** **behaviour change.** The pickup OTP no longer creates inventory lots; it records `confirmed_qty` and the job is `picked_up` (in transit). New RPC `admin_receive_donation(p_id, p_items)` (edge route `admin-api/assignments/receive`) takes the counted whole kits per item, creates the `received` lots plus movements (reason `hub receipt`), runs the reserve check and opens a `hub_shortfall` incident when a count differs from what the driver confirmed. Once per job; old-flow donations with lots are refused with `already_received`. **Decision (b):** donated stock counts from the hub count.
- **`get_tracking`** returns `hub_received_at` so the donor sees "delivered to hub".
- **Audit:** new actions `hub_received`, `hub_pickup_confirmed`, `hub_dropoff_completed`.
- **Tested** on a scratch PostgreSQL with a reduced schema; not on the Supabase project.
- **Apps:** admin count screen; donor screen shows the new step.

## 2026-11-22 (driver issue reporting)

- **Migration `20261122191000_driver_report_issue.sql`:** new `driver_report_issue(p_id, p_type, p_note)` (edge route `volunteer-api/assignments/report-issue`). `p_type` is `pickup_refused` or `items_mismatch`, note 2-500 characters. It opens an incident that keeps the reporting driver, releases the job back to offers with that driver excluded and sets the request back to `awaiting_assignment`. `admin_list_incidents` shows the driver. Donation pickups only (resource requests were added by `20261123000300`). **Not tested against real data.**

## 2026-11-22 (donor can raise and add items)

- **Migration `20261122190000_donor_edit_items.sql`:** `requester_update_pickup_qty` now lets the donor lower, raise, remove (qty 0) and add items (`{ item_type, qty >= 1 }`) until the driver enters the pickup OTP. A raised or added item differs from the approved quantity, so the driver must confirm it (`quantity_changed`). New error `invalid_quantity`. **Decision (d).** Not tested against real data.

## 2026-11-22 (kits only)

- **Migration `20261122181000_kit_units_whole_numbers.sql`:** every unit is `kit` and every quantity a whole number, on `request_items` and `inventory_lots` (check constraints plus trigger `fn_enforce_whole_kits`). Other units sent become `kit`; fractions are refused with `invalid_quantity`. Existing fractional rows are **rounded by the migration**: check hosted data first, because rounding changes stock numbers. `submit-request` now requires a whole-number `qty` and no longer needs `unit`.

## 2026-11-22 (reserve counts approvable stock, district config, reserve re-alert)

- **Migration `20261122183000_reserve_counts_ready_to_ship.sql` (E6):** the low-stock check counts only `ready_to_ship` stock minus reserved (same rule as approval and `inventory_available`). This **replaces** the rule in the 2026-11-22 reserve alerts entry below (received, processing and ready_to_ship). Flags are reset without sending an alert. Counted hub stock joins the reserve once the admin moves it to `ready_to_ship`.
- **Migration `20261122182000_district_public_and_reserve_realert.sql`:** E4: `get_district_config()` (anon-callable) and route `public-api/district` replace direct reads of `app_settings`, which stopped being public with `settings_public_read` dropped in `20261122113715`. E7: `admin_set_reserve_level` resets the alert flag when the level changes, so a category already below its new level alerts once straight away.
- **New `scripts/check_push_setup.sql`** (E5): read-only check of the one-time push setup (vault entries, `pg_net`, `pg_cron`, cron jobs, device and outbox counts).

## 2026-11-22 (one driver-location system)

- **Migration `20261122180000_cleanup_driver_location_and_nearby.sql` (E2, E3):** `update_my_location` (`volunteer_locations`) is the only driver-location system; `driver_latest_location`, its view and trigger are dropped. **Delete** the Edge Functions `update-driver-location`, `get-driver-location` and `get_nearby_requests` (folders and deployed copies). `nearby_offers` (`volunteer-api/offers/nearby`) replaces the last one.

## 2026-11-22 (approval creates driver offers)

- **Migration `20261122150000_approval_assignments_nearby_offers.sql`:** `admin_approve_request` calls `create_assignments` in the same transaction, so drivers see an approved request (and get a push) without a separate Assign step. `requests/assign` stays for re-creating offers. Adds `nearby_offers(p_lat, p_lng, p_radius_km)` (edge route `volunteer-api/offers/nearby`). **Decision (a).** Not tested against real data.

## 2026-11-22 (server-side route preview for offers)

- **Why:** before a driver accepts, `my_offers` and `assignments/detail` show only an approximate position and never the hub, so the app could not preview the full route. The preview is now built on the server from exact points.
- **Migration `20261122170000_offer_route_points.sql`:** new `offer_route_points(p_user, p_id)`, **service role only** (revoked from anon and authenticated, because it returns exact coordinates). Same visibility rule as `my_assignment_detail`: an open eligible offer, or your own unfinished assignment; anything else is `not_found`. Returns `{ kind, assignment_type, points[] }` in driving order after the driver: donation donor then hub, resource request hub then requester, other kinds the requester. The hub is read live from `app_settings` `central_inventory`, not from `route_snapshot`, so it is correct even for offers created before the hub moved. Errors `unauthorized | forbidden | not_found | hub_not_configured`. Tested on a scratch PostgreSQL with 14 access cases. That test found and fixed a NULL bug: on an open offer `volunteer_id` is null, and an unguarded check let wrong-tier and declined volunteers through; the whole check is now wrapped in `coalesce(..., false)`.
- **New Edge Function `get-offer-route`** (`POST`, volunteer JWT): body `{ id, lat, lng, costing? }`. Calls `offer_route_points`, sends driver + points to Valhalla, and returns only `{ kind, assignment_type, costing, shape_precision, summary, legs: [{ to, shape, length, time }] }`. No coordinates of the donor, requester or hub, no street names, no steps; nothing is saved; Valhalla's error text is never returned. Shape encoding is polyline precision 5, the same as `get-route`. Type-checked with Deno and run against a mocked database and routing service (11 cases).
- **Unchanged:** `get-route`, `my_offers`, `my_assignment_detail`, `route_snapshot`, `scripts/check_function_privileges.sql` (a service-role-only function needs no allow-list entry).
- **Deploy:** `supabase db push`, then `supabase functions deploy get-offer-route`. Uses the same `VALHALLA_URL`, `VALHALLA_CLIENT_ID` and `VALHALLA_PROXY_SECRET` as `get-route`. Run `scripts/check_function_privileges.sql` afterwards.
- **App:** call it when the volunteer opens an offer, with the phone's GPS position, and draw every leg. Not rate limited beyond the Valhalla timeout.

## 2026-11-22 (public map shows completed work only)

- **Migration `20261122160000_public_map_completed_only.sql`** replaces `map_markers()`. Layers are now only `pickup` (blue: donation received from a user, `picked_up_at` within 6 h) and `fulfilled` (green: resource request delivered, `fulfilled_at` within 12 h, `kind = resource_request` only). A donation dropped at the hub stays in `pickup` until 6 h after pickup (before, it jumped into `fulfilled`). The `donation` and `need` layers are removed, so nothing waiting for approval or still in progress is public. Output shape, rounding and privacy are unchanged. A delivery reported short (`partially_fulfilled`) still counts as delivered. Tested on a scratch PostgreSQL + PostGIS with 12 cases (not on the Supabase project).
- **`send-push`:** the `low_stock` broadcast now reads `push_recipients_all()` page by page. PostgREST returns at most 1000 rows per call, so with more than 1000 devices the rest would never have been told.
- **App:** the Explore screen must stop expecting `donation` and `need` markers and draw `pickup` as blue and `fulfilled` as green.
- **Deploy:** `supabase db push`, then `supabase functions deploy send-push`. `public-api` needs no redeploy.

## 2026-11-22 (hub moved to Kanchanpur, reserve alerts)

- **Hub:** migration `20261122140000_hub_to_fwu_soe.sql` upserts `app_settings` key `central_inventory` to FWU-SOE, Kanchanpur (28.954657907336678, 80.17888176615499), and rewrites the hub point inside `route_snapshot` of every unfinished assignment. The seed scripts, `docs/DEMO-SETUP.md` and `docs/REMOTE_SEED.md` no longer mention the Kathmandu placeholder. **Not yet run against a database.**
- **Reserve alerts, migration `20261122141000_reserve_alerts.sql`:** new table `inventory_reserve_levels` (one row per `item_type`, whole kits, `min_qty` 0 = off; starts at 10 as a placeholder). Stock for a category = `sum(quantity - reserved_qty)` over lots in phase received, processing or ready_to_ship, so donated stock counts from pickup. A statement-level trigger on `inventory_lots` runs `_reserve_check()`: the first time a category falls below its reserve it queues one `low_stock` row in `push_outbox`; when stock is back at or above the reserve the flag resets. Nothing is sent for the starting state.
- **Push outbox:** `kind` also allows `low_stock`; `assignment_id`, `request_id` and `assignment_type` are now nullable; new column `item_type`. `push_claim_batch` returns `item_type` as well. `send-push` broadcasts `low_stock` to `push_recipients_all()` (every device seen in the last 90 days, volunteers and normal users). Payload: `{ type: "low_stock", item_type }`, no personal data.
- **Devices:** `device_tokens.profile_id` is nullable. New anon RPC `register_public_device_token(p_token, p_platform)`, exposed as `POST /functions/v1/public-api/device-token` with `{ token, platform }` (token 20-4096 characters, platform android, ios or web). It never changes the owner of a token that already belongs to a volunteer.
- **Admin:** `POST /functions/v1/admin-api/stock/reserve-levels` returns `[{ item_type, min_qty, stock, below_reserve, last_alert_at }]`. `POST /functions/v1/admin-api/stock/reserve-levels/set` with `{ item_type, min_qty }` sets a level (whole number, 0 to 1000000) and runs the check at once. Errors: `forbidden`, `invalid_items` (unknown category), `invalid_qty`.
- **Scripts:** `scripts/check_function_privileges.sql` allow-lists the three new RPCs.
- **Deploy:** `supabase db push`, then `supabase functions deploy send-push public-api admin-api` straight away (an old `send-push` would mark `low_stock` rows as done without sending). Run `scripts/check_function_privileges.sql` afterwards.
- **Not done here:** the mobile app does not register a device token for normal users yet, and the admin app has no screen for reserve levels.

## 2026-11-22 (volunteers with more than one type)

- **Why:** one volunteer can now be both driver and doctor. Before, an application and a profile had a single `volunteer_type`, so a person could only get A+B or A+C.
- **Migration `20261122000012_multi_volunteer_types.sql`:** `volunteer_applications.volunteer_types volunteer_type[]` (backfilled from `volunteer_type`). `volunteer_type` stays as the primary type. A before-insert/update trigger keeps the two columns consistent (empty list becomes `{volunteer_type}`, the primary type is always in the list), so seed scripts that only set `volunteer_type` keep working. The two unnamed document checks are replaced by named ones (`volunteer_applications_driver_docs_chk`, `_doctor_docs_chk`, `_types_chk`): a licence is required when the list holds `driver`, a service card when it holds `doctor`. The trigger function is `service_role` only. **Not yet run against a database.**
- **`create-upload-urls`:** accepts `volunteer_types` (array) and allows the union of the document kinds. The single `volunteer_type` is still accepted.
- **`submit-volunteer-application`:** accepts `volunteer_types` (array). Licence fields are required if `driver` is in it, service-card fields if `doctor` is in it. Stores the list and the primary type (doctor, then driver, then manpower). The single `volunteer_type` is still accepted; `volunteer_types` wins if both are sent. `invalid_type` is also returned for an empty list, a non-list or an unknown value.
- **`approve-volunteer`:** `categories` is now the union over all types of the application, so driver + doctor gets `A, B, C`. Applications from before the migration are handled the same way (their list is just their one type). The audit entry now also records `volunteer_types`.
- **New `supabase/functions/_shared/volunteer_types.ts`:** the type to category and document-kind rules, used by the three functions above (the category map moved out of `approve-volunteer`).
- **No change** to `profiles` (still `volunteer_type` plus `categories`), the volunteer RPCs, `_tier_open_to` or the login and `auth-me` payloads: they already read `categories`. Contract is v1.5.
- **Deploy:** `supabase db push`, then `supabase functions deploy create-upload-urls submit-volunteer-application approve-volunteer`. Run `scripts/check_function_privileges.sql` afterwards.
- **Not done here:** admin app screens still show one type per volunteer, and the mobile registration screen does not call the API yet.

## 2026-11-22 (first full run on the hosted demo project)

- **Result:** `npm run test:api` against the hosted demo project passed: `sahayogi-edge-api` 37 requests / 0 failed, `sahayogi-flows` 86 requests / 0 failed. 28 of 43 Edge endpoints have a Postman request; the sign-up, password-reset, upload, route, driver-location, volunteer-approval and `send-push` functions are not covered yet.
- **Behaviour:** `admin-api` now answers a missing, invalid or expired token with `401 unauthenticated` (it was `403 forbidden`). `403 forbidden` is only for a signed-in user who is not an admin. Same as `volunteer-api`. Clients should treat 401 as "refresh or sign in again". Change is in `supabase/functions/_shared/rpc.ts`.
- **Tests:** device-token test now sends a token of at least 20 characters (the RPC requires 20-4096). Removed a contradictory `no error` assertion from the `skip OTP early` flow step (the expected result is a 409 `otp_required` error).
- **Deploy note:** `submit-request` must be redeployed with the rest (`supabase functions deploy`, no names). A stale copy did not return `request_id`, which broke every flow step that uses it.

## 2026-11-22 (test runner and demo deploy)

- **Tests:** `scripts/tests/matrix.mjs` (+ `lib.mjs`) runs the concurrency, RLS and role rows of `TEST-MATRIX.md` as real roles over HTTP. `npm run test:matrix` and `test:matrix:fast` in `scripts/`. Not yet run against a project.
- **Demo project:** `scripts/demo_deploy.sh` and `scripts/demo_deploy.ps1` (link, `db push --include-seed`, secrets, deploy all functions), `scripts/demo_vault_secrets.sql` (vault entries for send-push), `supabase/functions/.env.demo.example`, `docs/DEMO-SETUP.md`.
- **Postman:** `postman/sahayogi-edge-api.postman_collection.json` and `postman/demo.postman_environment.json` cover admin-api, volunteer-api and public-api, including the 401/403/404 cases. Edge API endpoints are documented in `docs/API-EDGE.md`.

## 2026-11-22 (migrations 000008 and 000009 rebuilt)

- **Why:** `20261122000008_email_otp.sql` and `20261122000009_push_outbox.sql` were 0 bytes in `Sahayogi-Nepal-test.zip` (issue 13). Both were rebuilt from the code that depends on them (`_shared/otp.ts`, the auth functions, `send-push`) and from the entries below. **Not yet run against a database.** If the originals exist in Git or on a project that already applied them, keep the originals and discard these.
- **000008:** `email_otps` (unique per email + purpose), `auth_attempts.kind` widened with `otp_send | otp_verify`, `volunteer_applications.email_verified_at`, `purge_email_otps()`, `revoke_user_sessions(uuid)`. Service role only.
- **000008 (addition):** pg_cron jobs `purge-email-otps` (daily 03:23 UTC, calls `purge_email_otps()`) and `purge-auth-attempts` (daily 03:29 UTC, calls `purge_auth_attempts()`). Both functions existed but were never scheduled. Re-running the migration replaces the jobs. Not yet run.
- **000009:** `push_outbox`, statement-level triggers on `assignments` (new offer, released back to pool), `_push_kick()` (pg_net + vault entries `push_function_url` and `push_secret`), `_push_enqueue_escalations()`, `_push_tick()`, `push_claim_batch(int)`, `push_recipients(uuid, text)`, pg_cron jobs `push-escalations` (every minute) and `purge-push-outbox` (daily). Service role only.

## 2026-11-22 (function privileges clean-up)

- **Migration `20261122000011_function_privileges.sql`:** closes issue 11. `audit_row_hash`, `fn_export_latest_audit_hash`, the four trigger functions (`fn_audit_logs_hash_chain`, `fn_audit_logs_append_only`, `fn_assignment_sync_driver_location`, `auto_assign_request_district_id`) and any other non-RPC function in `public` (push and email OTP helpers included) are now `service_role` only. A sweep applies the rule to everything not on the client RPC list, and the migration fails and rolls back if `anon` or `authenticated` can still execute something outside its list.
- **`is_admin()` stays executable by `anon` and `authenticated` on purpose:** RLS policies and the volunteer-docs storage policy call it as the requesting role. It returns false for anon.
- **No payload or behaviour change for the apps.** Contract stays v1.4.
- **New `scripts/check_function_privileges.sql`:** query 1 returns only violations (zero rows = pass); run it after every `supabase db push`.

## 2026-11-22 (get-route complete)

- **Migration `20261122000010_routes.sql`:** new `routes` table (user, optional `assignment_id`, origin and destination, costing, distance, duration, first-leg `shape`, all `legs` as jsonb). RLS: a user reads their own rows, admins read all; no client writes (the function uses the service role). Closes the routes-table gap.
- **Edge Function `get-route`:** `save: true` now works and accepts an optional `assignment_id` (must be the caller's own assignment, or the caller is an admin). Response adds `legs` (one entry per leg) next to `shape`, so routes with three or more points (driver, hub, requester) are not cut to the first leg. Locations are limited to 2-10.
- **Behaviour changes:** `strict_nepal` now defaults to true (send `false` to opt out). Suspended accounts get `403 account_suspended`. Valhalla error text is logged, not returned. Upstream calls time out after 15 s. `costing_options` must be a small object (`invalid_costing_options`). New error codes: `account_suspended`, `invalid_costing_options`, `invalid_assignment_id`, `not_found`.
- **Contract:** v1.4. The planned `routes` item is removed.

## 2026-11-22 (push notifications)

- **Migration `20261122000009_push_outbox.sql`:** new `push_outbox` table (no client access), triggers that queue a `new_offer` row when an assignment is inserted as `offered` or released back to the pool, `_push_enqueue_escalations()` (tier A, once per assignment), `_push_kick()` (calls the function through `pg_net`), and service-role-only `push_claim_batch(p_limit)` and `push_recipients(p_assignment, p_kind)`. pg_cron job `push-escalations` runs every minute (queues escalations and retries failed rows); `purge-push-outbox` deletes finished rows after 7 days.
- **Edge Function `send-push`** plus `_shared/fcm.ts` (FCM HTTP v1, service-account JWT, no SDK). Listed in `config.toml` with `verify_jwt = false`; it is protected by the `x-push-secret` header instead.
- **Behaviour:** who gets a push uses the same rule as `my_offers`. Payload is IDs only (`type`, `assignment_id`, `request_id`); the OTP is never pushed. Dead tokens are removed. A row is tried up to 5 times.
- **Setup (once per project):** secrets `PUSH_WEBHOOK_SECRET`, `FCM_SERVICE_ACCOUNT` (and `PUSH_DRY_RUN=true` locally only); two vault entries `push_function_url` and `push_secret`; `supabase functions deploy send-push`. Without the vault entries nothing is sent and the outbox just waits.
- **Not audited on purpose:** no business state changes and the volume would flood the hash chain.
- **Flutter (Person 1):** call `register_device_token` on start and on token refresh; handle `data.type` `new_offer | escalated` by opening the offer or refreshing `my_offers()`; create a high-importance Android channel.
- **Contract:** v1.3. The Push notifications section replaces the planned item.

## 2026-11-22 (email OTP for sign-up and forgot password)

- **Migration `20261122000008_email_otp.sql`:** new `email_otps` table (one row per email + purpose, HMAC hashes only, no client access), `auth_attempts.kind` now also allows `otp_send | otp_verify`, new column `volunteer_applications.email_verified_at`, `purge_email_otps()` and `revoke_user_sessions(uuid)` (both service role only).
- **Volunteer sign-up:** new `send-signup-otp` and `verify-signup-otp`. `submit-volunteer-application` now requires `email_verification_token` (from `verify-signup-otp`) and returns `403 email_not_verified` without it. The token is spent only when the application is saved. **Breaking for the Flutter registration form:** it must add the email-code step before submitting.
- **Forgot password:** `request-password-reset` now emails a 6-digit code instead of a link (same generic 200 answer). New `verify-reset-otp` (returns a one-time `reset_token`) and `reset-password` (sets the new password, signs out every session, clears failed-login counters, audit action `password_reset`).
- **Behaviour:** code valid 10 min, 5 guesses per code (counted before comparing, so parallel guesses cannot bypass it), 60 s resend cooldown, sign-up token 30 min, reset token 10 min, both single use and bound to the email. Limits per hour: 5 codes per email and 15 per IP; 10 wrong codes per email and 30 per IP per 15 min.
- **Behaviour:** `reset-password` also confirms the email, so a volunteer whose invite link expired can set a first password this way. The invite link flow for newly approved volunteers is unchanged.
- **Email delivery:** OTP emails go out through Gmail SMTP from the functions (`GMAIL_ADDRESS`, `GMAIL_APP_PASSWORD` in `supabase/functions/.env`). New optional vars `OTP_PEPPER`, `MAIL_FROM_NAME`, `OTP_DEV_LOG` (local only: prints the code in the `functions serve` terminal).
- **Config:** four new functions listed in `config.toml` with `verify_jwt = false`.
- **Web:** the admin app's `/set-password/` page offers email, code, and a new password when there is no valid invite link.
- **Docs/Postman:** `api-auth.md` v2, new Postman requests under Auth and Volunteer application, new rows in the test matrix.
- **Known:** Flutter `volunteer_login_screen.dart` still shows "Password reset is not connected yet" and the registration screen does not send the token. Both are Person 1 work against this contract. `create-upload-urls` is still open to anyone (IP-throttled), not gated by the email token.

## 2026-11-22 (RPC parts 3 to 5)

- **Migration `20261122000005_rpc_progress_otp_tracking.sql`:** `update_assignment_state` (forward-only), `driver_verify_otp` (15-minute expiry, 5-attempt lock, quantity-changed handling), `requester_get_otp`, `requester_update_pickup_qty`, `requester_confirm_delivery`, `get_tracking`, plus internal helpers `_request_id_by_token` and `_active_otp_assignment` (no client grant). The four requester RPCs and `get_tracking` are callable without signing in; the token hash is checked inside.
- **Migration `20261122000006_rpc_map_volunteer.sql`:** `map_markers` (anon-callable, rounded to 2 decimals, pickup layer 6 h, fulfilled layer 12 h), `admin_map_markers`, `update_my_location`, `my_stats`, `register_device_token`.
- **Migration `20261122000007_rpc_inventory_incidents.sql`:** `admin_import_stock`, `admin_move_lot` (partial moves split the lot), `admin_list_incidents`, `admin_resolve_incident`, `admin_list_audit` (keyset pagination, optional action/entity filter). Every function checks `is_admin()` first.
- **Behaviour:** a wrong OTP does not raise an error. `driver_verify_otp` returns `{ ok: false, reason }` (`invalid_otp | otp_locked | otp_expired | otp_used | otp_not_issued | quantity_changed`) so the attempt counter is not rolled back. Wrong ref or token on the requester RPCs is always `not_found`.
- **Behaviour:** each `requester_get_otp` call issues a new code and cancels the previous live one (only a hash is stored, so a code cannot be shown twice). Limit: 10 codes per assignment and purpose per hour.
- **Behaviour:** `delivery -> delivered` and `pickup -> picked_up` cannot be set with `update_assignment_state` (error `otp_required`); only `driver_verify_otp` does that. Delivery OTP dispatches the reserved stock; pickup OTP adds `received` lots from the confirmed quantities.
- **Behaviour:** a short-delivery report sets the assignment to `disputed` and the request to `partially_fulfilled`. Dismissing the incident puts the request back to `fulfilled`; resolving it keeps `partially_fulfilled`.
- **Audit:** new actions `otp_issued`, `otp_locked`, `donor_qty_changed`, `pickup_confirmed`, `delivery_completed`, `assignment_state_changed`, `incident_opened`, `incident_under_review | resolved | dismissed`, `stock_imported`, `lot_moved`. `update_my_location` is not audited on purpose.
- **Contract:** v1.2. Planned RPC list replaced by LIVE sections; one `docs/samples/<rpc>.json` per new RPC added. Only push notifications and the `routes` table remain planned.
- **Docs:** README status updated; `REMOTE-SEED.md` links corrected to `REMOTE_SEED.md`.
- **Known:** the admin app still calls `admin_review_request`, `admin_set_accepted_qty` and `admin_review_volunteer`, which do not exist. The live names are `admin_approve_request` and `admin_decline_request`; there is no volunteer-review or accepted-quantity RPC yet (volunteers go through `approve-volunteer`).

## 2026-11-22 (RPC parts 1 and 2)

- **Migration `20261122000003_rpc_admin_requests.sql`:** `admin_list_requests`, `admin_approve_request` (FIFO stock reservation under row locks, all-or-nothing), `admin_decline_request`, `admin_dashboard_counts`. Granted to `authenticated`, `is_admin()` checked inside.
- **Migration `20261122000004_rpc_assignments.sql`:** `create_assignments`, `my_offers`, `my_assignment_detail`, `claim_assignment`, `decline_assignment`, plus the internal `_tier_open_to` helper (no client grant). The exactly-{A}-for-60-s rule is now live in `my_offers` and `claim_assignment`.
- **Behaviour:** offers and unclaimed detail expose only an approximate location (2 decimals) and no requester contact; the exact route and requester name/phone appear after a claim.
- **Behaviour:** a volunteer can hold only one assignment per request (`already_on_request`); declining your own accepted assignment releases it back to the pool.
- **Contract:** v1.1, new LIVE RPC section; samples added under `docs/samples/`.

## 2026-11-22

- **Fix:** `requireDriver` / `requireDoctor` tested `profiles.role` (only `volunteer | admin`), so they rejected every driver and doctor. They now check `categories` (`B` / `C`) on an active volunteer. All role guards share one profile lookup.
- **Audit:** every Edge Function now writes through `audit()` (`append_audit_log`) instead of inserting into `audit_logs` directly, which could put ids out of chain order. Affects `approve-volunteer`, `admin-set-account-status`, `admin-login`.
- **Migration `20261122000002_submit_request_rpc.sql`:** new `submit_request` RPC (service role only): request + items in one transaction, 5-per-phone-per-hour limit, pilot-district bounds check, audit row.
- **`submit-request` changes:** response now includes `request_id`; new errors `outside_service_area` and `too_many_requests` (429). Locations outside the pilot district's bounds are now rejected (before: anywhere in Nepal). Field names stay `requester_name` / `requester_phone`.
- **Config:** `get-route` listed explicitly in `config.toml`. Unused guard imports removed from `get-route`.
- **Postman:** donation sample moved from Pokhara to Lalitpur so it is inside the pilot bounds.
- **Seed:** `20261122000001_seed_app_settings.sql` seeds `app_settings` rows `district` (pilot: Kathmandu, public-readable) and `central_inventory` (hub, not public). Hub coordinates are a placeholder.
- **Seed:** `supabase/seeds/nepal_districts.sql` is now idempotent (upserts instead of `DELETE`), safe to re-run on a hosted project.
- **Scripts:** `seed_extra.mjs` fills every table (applications, assignments in every state, events, OTP challenges, incidents, reservations, locations, device tokens, auth attempts, audit log, checkpoint).
- **Scripts:** `reset_demo_remote.mjs` clears operational tables on a hosted project and reseeds. `audit_logs` is never cleared.
- **Scripts:** scripts read flags from `.env` so they work on Windows PowerShell.
- **Docs:** API contract rewritten to match the code (v1). Old v0 items (`rice`, `district` field, `SN-` prefix, `public_map_markers` view) removed.

## 2026-11-21

- Audit log rebuilt as an append-only hash chain (`append_audit_log`, `verify_audit_chain`, 2-hourly checkpoint). Columns are now `date` and `hash_value`.
- Nepal districts with polygons; `requests.district_id` is set by trigger from the point. `districts.lat/lng` dropped.
- Added `get-route` (Valhalla), login and password-reset functions, volunteer application flow.
