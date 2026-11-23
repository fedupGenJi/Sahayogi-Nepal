import { FormEvent, useEffect, useMemo, useState } from 'react';
import { createClient, type Session } from '@supabase/supabase-js';

type Screen = 'checking' | 'password' | 'done' | 'email' | 'code';
type ApiResult = { ok: boolean; data: Record<string, unknown> | null; error: { code?: string; message?: string; attempts_left?: number } };

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

// Keep invite-link auth isolated from the signed-in admin app session.
const authClient = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { flowType: 'implicit', detectSessionInUrl: true, persistSession: false, autoRefreshToken: false },
});

const passwordRules = [
  { key: 'length', label: 'At least 10 characters', test: (value: string) => value.length >= 10 },
  { key: 'lowercase', label: 'A lowercase letter', test: (value: string) => /[a-z]/.test(value) },
  { key: 'uppercase', label: 'An uppercase letter', test: (value: string) => /[A-Z]/.test(value) },
  { key: 'number', label: 'A number', test: (value: string) => /[0-9]/.test(value) },
  { key: 'symbol', label: 'A symbol (for example ! @ # $)', test: (value: string) => /[^A-Za-z0-9]/.test(value) },
];

async function callAuthFunction(name: string, body: Record<string, string>): Promise<ApiResult> {
  try {
    const response = await fetch(`${supabaseUrl}/functions/v1/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: supabaseAnonKey },
      body: JSON.stringify(body),
    });
    const result = await response.json().catch(() => null);
    return {
      ok: response.ok,
      data: result?.data ?? null,
      error: result?.error ?? { code: 'request_failed', message: 'Something went wrong. Please try again.' },
    };
  } catch {
    return { ok: false, data: null, error: { code: 'network', message: 'Could not connect. Check your connection and try again.' } };
  }
}

function readLinkError() {
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''));
  return hash.get('error_description') ?? new URLSearchParams(window.location.search).get('error_description');
}

export default function SetPasswordPage() {
  const [screen, setScreen] = useState<Screen>('checking');
  const [mode, setMode] = useState<'invite' | 'otp' | null>(null);
  const [email, setEmail] = useState('');
  const [otp, setOtp] = useState('');
  const [resetToken, setResetToken] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [busy, setBusy] = useState(false);
  const [resendIn, setResendIn] = useState(0);

  const checks = useMemo(() => passwordRules.map((rule) => ({ ...rule, valid: rule.test(password) })), [password]);
  const canSave = checks.every((rule) => rule.valid) && password === confirmPassword && confirmPassword.length > 0;

  useEffect(() => {
    const setFromSession = (session: Session | null) => {
      if (!session) return false;
      setMode('invite');
      setEmail(session.user.email ?? '');
      setScreen('password');
      window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}`);
      return true;
    };

    let ready = false;
    const { data: listener } = authClient.auth.onAuthStateChange((event, session) => {
      if (!ready && (event === 'PASSWORD_RECOVERY' || event === 'SIGNED_IN' || event === 'INITIAL_SESSION')) {
        ready = setFromSession(session);
      }
    });

    const timeout = window.setTimeout(async () => {
      if (ready) return;
      const { data } = await authClient.auth.getSession();
      if (setFromSession(data.session)) return;
      const linkError = readLinkError();
      if (linkError) setError(linkError.replace(/\+/g, ' '));
      setScreen('email');
    }, 1200);

    return () => {
      window.clearTimeout(timeout);
      listener.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (resendIn <= 0) return;
    const timer = window.setTimeout(() => setResendIn((left) => Math.max(0, left - 1)), 1000);
    return () => window.clearTimeout(timer);
  }, [resendIn]);

  const sendCode = async (address: string) => {
    const result = await callAuthFunction('request-password-reset', { email: address });
    if (!result.ok) return result;
    setEmail(address);
    setOtp('');
    setError('');
    setSuccess('');
    setScreen('code');
    setResendIn(Number(result.data?.resend_after ?? 60));
    return result;
  };

  const onEmailSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const result = await sendCode(email.trim().toLowerCase());
    if (!result.ok) setError(result.error.message ?? 'Could not send a code. Try again.');
    setBusy(false);
  };

  const onCodeSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const result = await callAuthFunction('verify-reset-otp', { email, otp: otp.trim() });
    setBusy(false);
    if (!result.ok) {
      const attempts = result.error.attempts_left;
      setError(attempts !== undefined ? `${result.error.message} ${attempts} ${attempts === 1 ? 'try' : 'tries'} left.` : result.error.message ?? 'That code could not be verified.');
      return;
    }
    setMode('otp');
    setResetToken(String(result.data?.reset_token ?? ''));
    setPassword('');
    setConfirmPassword('');
    setScreen('password');
  };

  const onPasswordSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!canSave) return;
    setBusy(true);
    setError('');
    if (mode === 'otp') {
      const result = await callAuthFunction('reset-password', { email, reset_token: resetToken, new_password: password });
      if (!result.ok) {
        if (result.error.code === 'invalid_token') {
          setResetToken('');
          setPassword('');
          setConfirmPassword('');
          setScreen('email');
        }
        setError(result.error.message ?? 'Could not save your password. Try again.');
        setBusy(false);
        return;
      }
    } else {
      const { error: updateError } = await authClient.auth.updateUser({ password });
      if (updateError) {
        setError(updateError.message || 'Could not save your password. Try again.');
        setBusy(false);
        return;
      }
      await authClient.auth.signOut();
    }
    setBusy(false);
    setScreen('done');
  };

  const backToAdmin = () => {
    const basePath = window.location.pathname.replace(/set-password\/?$/, '');
    window.location.assign(`${basePath}#/login`);
  };

  return (
    <main className="login password-login">
      <section className="login__brand">
        <img className="login__logo" src="../images/HorizontalLogo.svg" alt="Sahayogi Nepal" />
        <p className="login__console">OPERATIONS CONSOLE</p>
        <p className="login__tagline">Support that reaches further.</p>
      </section>

      <section className="login__panel">
        <div className="auth-card password-card" aria-live="polite">
          {screen === 'checking' && <>
            <span className="password-eyebrow">ACCOUNT SECURITY</span>
            <h1>Checking your link</h1>
            <p className="auth-muted">Please wait while we verify your secure password link.</p>
            <div className="password-loader" role="status" aria-label="Checking link" />
          </>}

          {screen === 'password' && <>
            <span className="password-eyebrow">ACCOUNT SECURITY</span>
            <h1>{mode === 'invite' ? 'Set your password' : 'Choose a new password'}</h1>
            <p className="auth-muted">{email ? `Create a secure password for ${email}.` : 'Create a secure password for your account.'}</p>
            <form className="password-form" onSubmit={onPasswordSubmit} noValidate>
              <label className="field"><span>New password</span><input type="password" autoComplete="new-password" minLength={10} maxLength={128} value={password} onChange={(event) => setPassword(event.target.value)} required /></label>
              <label className="field"><span>Confirm password</span><input type="password" autoComplete="new-password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} required /></label>
              <ul className="password-rules" aria-label="Password requirements">
                {checks.map((rule) => <li className={rule.valid ? 'is-valid' : ''} key={rule.key}><span aria-hidden="true">{rule.valid ? '✓' : '○'}</span>{rule.label}</li>)}
                <li className={confirmPassword.length > 0 && password === confirmPassword ? 'is-valid' : ''}><span aria-hidden="true">{confirmPassword.length > 0 && password === confirmPassword ? '✓' : '○'}</span>Both passwords match</li>
              </ul>
              {error && <p className="auth-error" role="alert">{error}</p>}
              <button className="btn auth-submit auth-submit--primary" type="submit" disabled={!canSave || busy}>{busy ? 'Saving password…' : 'Save password'}</button>
            </form>
            {mode === 'otp' && <button type="button" className="password-text-button" onClick={() => { setError(''); setScreen('email'); }}>Start over</button>}
          </>}

          {screen === 'done' && <>
            <span className="password-success-icon" aria-hidden="true">✓</span>
            <span className="password-eyebrow">ALL SET</span>
            <h1>Password saved</h1>
            <p className="auth-muted">Your password is ready. Sign in to the Sahayogi Nepal admin console with your email and new password.</p>
            <button className="btn auth-submit auth-submit--primary" type="button" onClick={backToAdmin}>Go to admin sign in</button>
          </>}

          {screen === 'email' && <>
            <span className="password-eyebrow">ACCOUNT SECURITY</span>
            <h1>Set or reset password</h1>
            <p className="auth-muted">{error ? 'Your invite link may have expired. Request a one-time code to continue.' : 'Forgot your password, or is your invite link no longer working? We will email you a one-time code.'}</p>
            {error && <p className="auth-error" role="alert">{error}</p>}
            <form className="password-form" onSubmit={onEmailSubmit}>
              <label className="field"><span>Email</span><input type="email" autoComplete="email" maxLength={254} value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" required /></label>
              <button className="btn auth-submit auth-submit--primary" type="submit" disabled={busy || !email.trim()}>{busy ? 'Sending code…' : 'Email me a code'}</button>
            </form>
          </>}

          {screen === 'code' && <>
            <span className="password-eyebrow">VERIFY YOUR EMAIL</span>
            <h1>Enter your code</h1>
            <p className="auth-muted">If {email} has an active account, we sent a 6-digit code. It works for 10 minutes.</p>
            <form className="password-form" onSubmit={onCodeSubmit}>
              <label className="field"><span>6-digit code</span><input type="text" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} value={otp} onChange={(event) => setOtp(event.target.value.replace(/\D/g, '').slice(0, 6))} placeholder="123456" required /></label>
              {error && <p className="auth-error" role="alert">{error}</p>}
              {success && <p className="auth-success" role="status">{success}</p>}
              <button className="btn auth-submit auth-submit--primary" type="submit" disabled={busy || otp.length !== 6}>{busy ? 'Checking code…' : 'Verify code'}</button>
            </form>
            <button className="password-text-button" type="button" disabled={busy || resendIn > 0} onClick={async () => {
              setBusy(true);
              const result = await sendCode(email);
              if (result.ok) setSuccess('A new code was sent.');
              else { setError(result.error.message ?? 'Could not resend the code.'); setResendIn(30); }
              setBusy(false);
            }}>{resendIn > 0 ? `Resend code in ${resendIn}s` : 'Resend code'}</button>
            <button className="password-text-button" type="button" onClick={() => { setError(''); setSuccess(''); setScreen('email'); }}>Use a different email</button>
          </>}
        </div>
      </section>
    </main>
  );
}
