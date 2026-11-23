alter table public.auth_attempts drop constraint if exists auth_attempts_kind_check;
alter table public.auth_attempts
  add constraint auth_attempts_kind_check
  check (kind in ('login', 'reset', 'apply', 'upload', 'otp_send', 'otp_verify', 'status_check', 'form_ai'));
