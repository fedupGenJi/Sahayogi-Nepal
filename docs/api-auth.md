# Sahayogi Nepal – Auth & Account API

Owner: Person 2 (Rujan Dhamala, Aakash Thakur). Status: **v2 – auth layer with email OTP** (sign-up and forgot password). Every change goes through a PR + a message in team chat.

Base URL: `https://<project-ref>.supabase.co` (local: `http://127.0.0.1:54321`)
Edge Functions: `POST {BASE}/functions/v1/<name>`
Required header on every call: `apikey: <ANON_KEY>` and `Content-Type: application/json`.
Protected calls also send `Authorization: Bearer <access_token>`.

> Only the **anon/publishable key** goes into Flutter and the admin web. The service-role key never leaves the backend.

---

## 0. Response format

```json
{ "data": { ... }, "error": null }
{ "data": null, "error": { "code": "invalid_credentials", "message": "Incorrect email or password." } }
```

| HTTP      | Meaning                                          |
| --------- | ------------------------------------------------ |
| 200 / 201 | success                                          |
| 400       | validation error (`error.code` says which)     |
| 401       | not signed in / wrong credentials                |
| 403       | signed in but not allowed (not admin, suspended) |
| 404 / 409 | not found / state conflict                       |
| 429       | throttled                                        |

### Error codes

| code                                                                                                     | Where                       | Show to user                                                                      |
| -------------------------------------------------------------------------------------------------------- | --------------------------- | --------------------------------------------------------------------------------- |
| `invalid_credentials`                                                                                  | both logins                 | "Incorrect email or password." (also returned for the wrong portal – on purpose) |
| `too_many_attempts`                                                                                    | login, reset, apply, upload, OTP send/verify | "Too many tries, wait and retry."                                                 |
| `account_suspended`                                                                                    | login, auth-me              | "Account suspended. Contact an admin."                                            |
| `unauthenticated`                                                                                      | auth-me                     | go to login                                                                       |
| `forbidden`                                                                                            | admin functions             | caller is not an active admin                                                     |
| `invalid_email` / `invalid_name` / `invalid_phone` / `invalid_type` / `invalid_citizenship_no` | apply                       | field error (`invalid_type` also covers upload: `volunteer_types` missing, empty, not a list or has an unknown value) |
| `license_required` / `service_card_required`                                                         | apply                       | field error (asked whenever `driver` / `doctor` is in `volunteer_types`)          |
| `invalid_files` / `invalid_path` / `document_missing`                                              | upload / apply              | re-upload                                                                         |
| `application_exists`                                                                                   | apply                       | "An application or account with this email already exists."                       |
| `invalid_state`                                                                                        | approve                     | already decided                                                                   |
| `reason_required`                                                                                      | approve (decline)           | admin must type a reason                                                          |
| `invite_failed`                                                                                        | approve                     | email could not be sent (check SMTP)                                              |
| `already_active`                                                                                       | approve (resend_invite)     | volunteer already has a password → use Forgot password                           |
| `email_not_verified`                                                                                     | apply                       | send the user back to the "enter code" step (token missing, used or expired)      |
| `resend_too_soon`                                                                                        | send-signup-otp             | "Wait N seconds" (`error.retry_after_seconds`)                                    |
| `email_failed`                                                                                           | send-signup-otp             | "Could not send the email, try again" (SMTP problem)                              |
| `invalid_otp`                                                                                            | verify-*-otp                | "That code is not correct" (`error.attempts_left` says how many tries remain)     |
| `otp_expired`                                                                                            | verify-*-otp                | code older than 10 min → ask for a new one                                        |
| `otp_locked`                                                                                             | verify-*-otp                | 5 wrong guesses → ask for a new code                                              |
| `weak_password`                                                                                          | reset-password              | field error (10+ chars, upper, lower, digit, symbol)                              |
| `invalid_token`                                                                                          | reset-password              | reset session expired or used → restart from the email step                       |

---

## 1. Roles and who can call what

| Caller            | Can use                                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------------------------- |
| Anyone (no login) | `send-signup-otp`, `verify-signup-otp`, `create-upload-urls`, `submit-volunteer-application`, `request-password-reset`, `verify-reset-otp`, `reset-password`, the set-password web page |
| Volunteer         | `volunteer-login`, `auth-me`, all volunteer RPCs (`my_offers`, `claim_assignment`, …)                  |
| Admin             | `admin-login`, `auth-me`, `approve-volunteer`, `admin-set-account-status`, all `admin_*` RPCs         |

Admin and volunteer have **separate login endpoints**. A volunteer's credentials sent to `admin-login` (and vice-versa) fail with the same `invalid_credentials` message.

> **Important for everyone:** the real protection is on the data, not the login screen. Every admin RPC/table is guarded by `is_admin()` and every volunteer RPC checks the caller's profile inside the database. A token from the volunteer login cannot approve anything.

---

## 2. Login

### POST `/functions/v1/admin-login`   (admin web only)

### POST `/functions/v1/volunteer-login`   (Flutter volunteer app)

Request

```json
{ "email": "driver1@demo.test", "password": "••••••••••" }
```

Response 200

```json
{
  "data": {
    "session": {
      "access_token": "eyJ...",
      "refresh_token": "abc...",
      "expires_in": 3600,
      "expires_at": 1795000000,
      "token_type": "bearer"
    },
    "profile": {
      "id": "uuid",
      "full_name": "Demo Driver 1",
      "email": "driver1@demo.test",
      "phone": "9800000001",
      "role": "volunteer",
      "volunteer_type": "driver",
      "categories": ["A", "B"]
    }
  },
  "error": null
}
```

Rules: 5 failed attempts per email (or 30 per IP) in 15 min → `429 too_many_attempts`. Suspended accounts get `403 account_suspended`.

**After login, hand the session to the SDK** so refresh + RPC calls work automatically:

Flutter (volunteer app)

```dart
final res = await supabase.functions.invoke('volunteer-login',
    body: {'email': email, 'password': password});
final d = (res.data as Map)['data'];
await supabase.auth.setSession(d['session']['refresh_token']);   // SDK refreshes tokens from now on
final profile = d['profile'];                                    // role, categories, volunteer_type

// errors
try { ... } on FunctionException catch (e) {
  final code = (e.details as Map?)?['error']?['code'];          // invalid_credentials, too_many_attempts, ...
}
```

Admin web (supabase-js)

```js
const r = await fetch(`${SUPABASE_URL}/functions/v1/admin-login`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', apikey: ANON_KEY },
  body: JSON.stringify({ email, password }),
});
const j = await r.json();
if (j.error) return showError(j.error.code);
await supabase.auth.setSession({
  access_token: j.data.session.access_token,
  refresh_token: j.data.session.refresh_token,
});
```

Logout: `supabase.auth.signOut()` (both apps).

### POST `/functions/v1/auth-me`

Header: `Authorization: Bearer <access_token>`. Returns `{ data: { profile } }` (same fields + `account_status`, `last_login_at`). Use on app start to confirm the saved session is still valid and still the right role. `401 unauthenticated` → send to login.

---

## 3. Volunteer sign-up (email OTP, then documents, no account yet)

Applicants are stored in `volunteer_applications` (staging). **No auth user exists until an admin approves.**
Since v2 the applicant must **prove they own the email** with a 6-digit code before an application is accepted.

```
send-signup-otp  ->  verify-signup-otp  ->  create-upload-urls  ->  submit-volunteer-application
 (email gets code)    (returns token)        (photos)                (sends the token back)
```

### Step 0a – POST `/functions/v1/send-signup-otp`   (public)

```json
{ "email": "sita@gmail.com" }
```

Response 200

```json
{ "data": { "message": "A 6-digit code has been sent to your email.", "expires_in": 600, "resend_after": 60 }, "error": null }
```

- Code is valid **10 minutes**, one live code per email (a new request replaces the old one).
- Resend cooldown **60 s** → `429 resend_too_soon` with `error.retry_after_seconds`.
- Limits: 5 codes per email and 15 per IP per hour → `429 too_many_attempts`.
- `409 application_exists` if the email already has a live application or an account (shown here so nobody fills the form for nothing).
- `502 email_failed` if the email could not be sent.

### Step 0b – POST `/functions/v1/verify-signup-otp`   (public)

```json
{ "email": "sita@gmail.com", "otp": "482913" }
```

Response 200

```json
{ "data": { "email_verification_token": "Zk3...", "expires_in": 1800 }, "error": null }
```

Keep the token in memory. It is valid **30 minutes**, works **once**, and only for this email.
Errors: `400 invalid_otp` (with `attempts_left`), `400 otp_expired`, `429 otp_locked` (5 wrong guesses, request a new code), `429 too_many_attempts` (10 wrong guesses per email or 30 per IP in 15 min).

### Step 1 – POST `/functions/v1/create-upload-urls`   (public)

```json
{
  "volunteer_types": ["driver", "doctor"],
  "files": [
    { "kind": "citizenship",  "content_type": "image/jpeg" },
    { "kind": "license",      "content_type": "image/jpeg" },
    { "kind": "service_card", "content_type": "image/jpeg" }
  ]
}
```

`volunteer_types` is a list, so one person can be driver and doctor. The old single `"volunteer_type": "driver"` is still accepted.
Allowed kinds are the union over the selected types: `manpower` → citizenship · `driver` → citizenship + license · `doctor` → citizenship + service_card. Send one entry per kind, citizenship is always required.
Images only: jpeg / png / webp, max 5 MB.

Response

```json
{ "data": { "uploads": [
  { "kind": "citizenship", "path": "docs/9f1c....jpg", "token": "eyJ...", "signed_url": "https://...", "content_type": "image/jpeg" },
  { "kind": "license",     "path": "docs/77ab....jpg", "token": "eyJ...", "signed_url": "https://...", "content_type": "image/jpeg" }
 ], "max_bytes": 5242880 }, "error": null }
```

Upload each file with its **token** (not a normal upload – anon users have no storage policy). Flutter:

```dart
await supabase.storage.from('volunteer-docs').uploadBinaryToSignedUrl(
    path, token, bytes, const FileOptions(contentType: 'image/jpeg'));
```

(Method name per `storage_client` in recent supabase_flutter; if your version differs, look for "signed upload URL" in its docs.)
(supabase-js: `supabase.storage.from('volunteer-docs').uploadToSignedUrl(path, token, file)`)

### Step 2 – POST `/functions/v1/submit-volunteer-application`   (public, needs the token)

```json
{
  "full_name": "Sita Sharma",
  "email": "sita@gmail.com",
  "email_verification_token": "Zk3...",
  "phone": "9801234567",
  "volunteer_types": ["driver"],
  "citizenship_no": "12-34-56-78901",
  "citizenship_photo_path": "docs/9f1c....jpg",
  "license_no": "01-06-00123456",
  "license_photo_path": "docs/77ab....jpg"
}
```

Doctor: use `"volunteer_types": ["doctor"]` and send `service_card_no` + `service_card_photo_path` instead of the licence fields.
Driver and doctor: use `"volunteer_types": ["driver", "doctor"]` and send **both** sets of fields. A missing licence returns `license_required`, a missing service card `service_card_required`.
The single `"volunteer_type": "driver"` field is still accepted; `volunteer_types` wins if both are sent. The stored `volunteer_type` is the primary type (doctor, then driver, then manpower).
Phone must be a Nepal mobile (`98XXXXXXXX` or `+97798XXXXXXXX`).

Response 201

```json
{ "data": { "application_id": "uuid", "status": "submitted" }, "error": null }
```

`email` must be the **same address that was verified**. A missing, used or expired token returns `403 email_not_verified`: send the user back to Step 0a. The token is only spent when the application is actually saved, so a validation error (bad phone, missing photo) does not burn it.

Limits: 500 per IP and 3 per phone per 24 h. One live application per email (`409 application_exists`).

Show the applicant: *"Application received. You will get an email with a link to set your password once an admin approves it."*

---

## 4. Admin reviews applications

### Read the queue (table, admin JWT)

```js
supabase.from('volunteer_applications').select('*').eq('review_status', 'submitted').order('created_at')
```

### View ID photos (admin JWT, short-lived URL)

```js
const { data } = await supabase.storage.from('volunteer-docs').createSignedUrl(path, 60); // seconds
```

Non-admins get nothing from this bucket.

### POST `/functions/v1/approve-volunteer`   (admin JWT)

```json
{ "application_id": "uuid", "decision": "approve", "note": "Documents verified" }
```

| decision          | Effect                                                                                                     | Extra                                         |
| ----------------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `approve`       | creates the auth user, profile (categories A / A+B / A+C by type, or the union when the applicant has several types: driver + doctor = A+B+C) and **emails a set-password link** | `note` optional                             |
| `decline`       | stores reason; no account created                                                                          | `note` **required** (min 3 chars)     |
| `resend_invite` | re-sends the link to an approved volunteer who never set a password                                        | if they already did → `409 already_active` |

Response: `{ "data": { "application_id": "...", "decision": "approve", "profile_id": "uuid" }, "error": null }`

> Declined applicants are not emailed automatically (Supabase only sends auth emails). Show the status in the admin panel; add an email provider later if needed.

### POST `/functions/v1/admin-set-account-status`   (admin JWT)

```json
{ "user_id": "uuid", "status": "suspended", "reason": "Under investigation" }
```

`status`: `suspended` | `active`. Suspended users cannot log in or refresh tokens, and all volunteer RPCs stop working for them immediately. An admin cannot change their own status.

---

## 5. Set password and forgot password

There are two separate ways to end up with a password:

| Situation                                   | How                                                                                      |
| ------------------------------------------- | ---------------------------------------------------------------------------------------- |
| First time, after an admin approved you     | Email with a **Set my password** link → admin app page `/set-password/`                   |
| Forgot password, or the invite link expired | **Email OTP**: `request-password-reset` → `verify-reset-otp` → `reset-password` (below)   |

The admin app's set-password page handles both paths: invite link first, then email → code → new password if the link is missing or expired. Flutter and the admin web can call the three endpoints directly.

```
request-password-reset  ->  verify-reset-otp  ->  reset-password
 (email gets code)          (returns reset_token)   (sends token + new password)
```

### Step 1 – POST `/functions/v1/request-password-reset`   (public)

```json
{ "email": "sita@gmail.com" }
```

Always answers `200` with the same body, whether or not the account exists (nobody can use it to find out who has an account):

```json
{ "data": { "message": "If that email belongs to an account, a 6-digit code has been sent.", "expires_in": 600, "resend_after": 60 }, "error": null }
```

- Code valid **10 minutes**; a new request replaces the old code; the server ignores requests within **60 s** of the last one (the response still says 200, so the app should run its own 60 s resend timer from `resend_after`).
- Only **active** accounts get a code. Suspended and unknown emails get the same 200 and no email.
- Works for admins and volunteers (same flow).
- Limits: 5 per email and 15 per IP per hour → `429 too_many_attempts`.

### Step 2 – POST `/functions/v1/verify-reset-otp`   (public)

```json
{ "email": "sita@gmail.com", "otp": "482913" }
```

Response 200

```json
{ "data": { "reset_token": "Zk3...", "expires_in": 600 }, "error": null }
```

`reset_token` is valid **10 minutes**, works **once**, only for this email. Errors are the same as `verify-signup-otp`: `invalid_otp` (+ `attempts_left`), `otp_expired`, `otp_locked`, `too_many_attempts`.

### Step 3 – POST `/functions/v1/reset-password`   (public, needs the token)

```json
{ "email": "sita@gmail.com", "reset_token": "Zk3...", "new_password": "N3w-Strong#Pass" }
```

Response 200: `{ "data": { "message": "Your password has been changed. Sign in with your new password." }, "error": null }`

- Password rule: 10–128 chars with upper, lower, digit and symbol → `400 weak_password` (message says what is missing).
- Bad, used or expired token → `400 invalid_token`: restart from Step 1.
- On success every existing session of that user is signed out, failed-login counters are cleared, the action is written to the audit log (`password_reset`), and the user signs in again via `volunteer-login` / `admin-login`.
- A volunteer whose invite link expired can use this flow to set their first password (the account is marked confirmed). No admin action needed.

Flutter

```dart
// 1. ask for a code (always succeeds visibly)
await supabase.functions.invoke('request-password-reset', body: {'email': email});

// 2. verify the code
final v = await supabase.functions.invoke('verify-reset-otp', body: {'email': email, 'otp': code});
final resetToken = (v.data as Map)['data']['reset_token'];

// 3. set the new password
await supabase.functions.invoke('reset-password',
    body: {'email': email, 'reset_token': resetToken, 'new_password': newPassword});

// errors (any step)
try { ... } on FunctionException catch (e) {
  final err = (e.details as Map?)?['error'];       // err['code'], err['message'], err['attempts_left']
}
```

### Email delivery

OTP emails are sent by the Edge Functions through the **Resend API** (`RESEND_API_KEY` + `MAIL_FROM_ADDRESS` in `supabase/functions/.env`; the sending domain must be verified in Resend). Supabase's own invite and recovery emails go through Resend SMTP (`[auth.email.smtp]` in `config.toml` locally, Auth > SMTP Settings on the hosted project). For local work without Resend, set `OTP_DEV_LOG=true` and read the code in the terminal running `supabase functions serve`.

---

## 6. Demo accounts (local / demo project only)

Created by `node --env-file=.env scripts/seed_demo.mjs` (or the users-only `scripts/seed_users.mjs`). For a hosted project see [`REMOTE_SEED.md`](REMOTE_SEED.md).

| Email                                | Role                 | Categories |
| ------------------------------------ | -------------------- | ---------- |
| admin@demo.test                      | admin                | –         |
| driver1@demo.test, driver2@demo.test | volunteer (driver)   | A, B       |
| general@demo.test                    | volunteer (manpower) | A          |
| doctor@demo.test                     | volunteer (doctor)   | A, C       |

Password: the `DEMO_PASSWORD` from `.env`, shared in the team chat (not in Git). Demo emails do not receive mail; use the real flow only with real Gmail addresses.

---

## 7. Quick tests (curl)

```bash
export SUPABASE_URL="http://127.0.0.1:54321"; export KEY="<anon key>"

# admin login
curl -s -X POST "$SUPABASE_URL/functions/v1/admin-login" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"admin@demo.test","password":"<demo password>"}'

# volunteer token must NOT work on the admin portal -> invalid_credentials
curl -s -X POST "$SUPABASE_URL/functions/v1/admin-login" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"driver1@demo.test","password":"<demo password>"}'

# volunteer calling an admin function -> 403 forbidden
curl -s -X POST "$SUPABASE_URL/functions/v1/approve-volunteer" -H "apikey: $KEY" \
  -H "Authorization: Bearer <volunteer access_token>" -H "Content-Type: application/json" \
  -d '{"application_id":"00000000-0000-0000-0000-000000000000","decision":"approve"}'

# sign-up OTP (local: code appears in the `functions serve` terminal when OTP_DEV_LOG=true)
curl -s -X POST "$SUPABASE_URL/functions/v1/send-signup-otp" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"newvolunteer@gmail.com"}'
curl -s -X POST "$SUPABASE_URL/functions/v1/verify-signup-otp" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"newvolunteer@gmail.com","otp":"<6-digit code>"}'

# forgot password
curl -s -X POST "$SUPABASE_URL/functions/v1/request-password-reset" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"driver1@demo.test"}'
curl -s -X POST "$SUPABASE_URL/functions/v1/verify-reset-otp" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"driver1@demo.test","otp":"<6-digit code>"}'
curl -s -X POST "$SUPABASE_URL/functions/v1/reset-password" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"driver1@demo.test","reset_token":"<reset_token>","new_password":"N3w-Strong#Pass"}'

# me
curl -s -X POST "$SUPABASE_URL/functions/v1/auth-me" -H "apikey: $KEY" -H "Authorization: Bearer <access_token>"
```

On Windows PowerShell, use `$env:KEY="..."` instead of `export`. Local invite emails appear in Inbucket: http://127.0.0.1:54324 (unless Resend SMTP is enabled). OTP emails do not go through Inbucket: with `OTP_DEV_LOG=true` and no Resend credentials the code is printed in the `functions serve` terminal.

---
