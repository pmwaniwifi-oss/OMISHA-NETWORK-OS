# OMISHA NETWORK OS Android app shell

One Flutter Android app package serves customer, ISP organization, and OMISHA workforce users. The login screen does not ask users to grant themselves roles. After authentication, the backend returns the memberships and capabilities the account is allowed to use.

## Current source

- `lib/main.dart`: single sign-in shell, server-returned workspace picker, capability display, workspace switching, and logout.
- `lib/api.dart`: HTTPS-only API client contract with bounded responses and separate identity/context-scoped tokens.
- `flutter_secure_storage`: stores the tokens in platform secure storage. The package currently uses Android's secure cryptographic storage; validate device/backup behavior during Android release hardening.
- `android-host/MainActivity.java` is a small native bridge to Android Credential Manager. The CI workflow generates the Flutter host, copies this bridge, and adds stable AndroidX Credential Manager 1.6.0 plus Google ID 1.2.0 dependencies. Android minSdk is 23. This is still source scaffolding, not a signed/build-ready release.

## Backend API contract required

The Go API/BFF must implement and secure these routes before login can work:

1. `POST /v1/auth/social/google/challenge` with no user-supplied identity. Return a short-lived `challenge_id` and cryptographically random `nonce`; store only its server-keyed fingerprint. Apply IP/device rate limits and single-use expiry.
2. `POST /v1/auth/social/google` with `challenge_id` and Google `id_token`. Validate Google's signature, issuer, expected server client ID, expiry, and exact nonce claim; atomically consume the matching unexpired challenge before issuing an OMISHA identity session. Never treat a whole Google ID token as globally one-use or trust role/tenant fields from the client.
3. `POST /v1/auth/challenges` with `identifier`; return a generic `challenge_id` response that does not reveal whether an account exists. The backend decides the allowed verification channel. It must rate-limit requests, make responses indistinguishable for unknown accounts, give codes a short lifetime and one-time use, and redact identifiers/codes from logs.
4. `POST /v1/auth/challenges/verify` with challenge ID and code; return a short-lived `identity_token`. This token may enumerate only memberships and activate an authorized context; it must not authorize customer, ISP, or platform business data.
5. `GET /v1/me/contexts` with the identity token; return server-authorized `context_id`, organization/workspace labels, role labels and display capabilities.
6. `POST /v1/me/contexts/activate` with a context ID returned by step 5; server revalidates membership and returns a short-lived tenant/workspace-scoped `access_token` plus its active context.
7. `GET /v1/me` with the scoped access token; return only the active workspace profile and capability display data.
8. `POST /v1/auth/logout`; revoke the identity session and all scoped tokens in its token family; the identity token is sent only as the Authorization bearer, never in the request body.

Every business endpoint must independently enforce user, role, tenant and record assignment. Hiding a screen in Flutter is not authorization. A request body cannot select a tenant, role, or capability. Customer, ISP staff, OMISHA workforce, and platform administration must have separate authorization scopes; platform or cross-tenant access is denied by default.

## Session handling

The app stores the short-lived identity token and active context access token in secure storage, never SharedPreferences. Google sign-in requests a fresh API challenge for each attempt and passes its nonce into Credential Manager; the raw Google token and nonce remain transient in memory. Context listing/switching uses only the membership token; customer/ISP/OMISHA business requests must use the server-issued context-scoped token. Logout clears both local tokens even if server revocation is temporarily unavailable. Expired sessions return the user to sign-in; no refresh-token flow is implemented.

Role/workspace metadata is display-only. Do not store subscriber lists, Aadhaar artifacts, payment credentials, or sensitive offline work in this shell. Offline mode is not implemented.

## Build after Flutter tooling is available

From this directory:

```sh
# The CI workflow generates the Android host and installs the native bridge/dependencies.
# For local builds, follow that workflow's host-generation, source-copy, Gradle dependency,
# and minSdk steps before running:
flutter pub get
flutter build apk --dart-define=OMISHA_API_BASE_URL=https://api.example.invalid/
```

Replace the example HTTPS URL only after the Go API is deployed with TLS and the identity/context endpoints above. Do not point the app at a live system until API authorization, session revocation, tenant isolation, account recovery, and cross-role access controls have been reviewed.

## Verification state

Flutter and Dart SDK were not present in the inspected workspace, so this source package has not been compiled or run. The Go endpoints above are a contract only and are not implemented by the current gateway. A production login, role workspace, mobile onboarding, or Android APK is not yet available.


## Google social sign-in

The Flutter UI calls a native Android Credential Manager bridge for Google sign-in. Each attempt first fetches a fresh challenge and passes its nonce to the Credential Manager Google ID-token request. Configure `OMISHA_GOOGLE_SERVER_CLIENT_ID` at build time with the server/web OAuth client ID created in OMISHA's Google Cloud project. Also register the final Android application ID and signing certificate fingerprints there. Do not put a client secret in the app or repository.

The app sends the Google ID token plus `challenge_id` to `POST /v1/auth/social/google`; the Go backend must verify token signature, issuer, audience, expiry and exact nonce claim against Google's current keys, then consume the challenge atomically. Use Google's stable subject as the provider identity. Do not accept client-supplied role/tenant data, auto-link accounts solely by a typed email, or grant employee/ISP roles from Google sign-in. Staff and ISP memberships require server-side invitation/approval; customer service still requires the applicable contact/subscriber checks. Request no Google data-access scopes beyond basic sign-in.

Neither Google challenge nor token exchange endpoint exists in the current Go gateway. The native bridge and nonce-aware Flutter contract are not yet verified in an Android build. Until OMISHA configures the OAuth project and the Go verifier/session API is implemented, Google login is not operational. The shell's OTP route is also a backend contract only.

## Games, reels, and monetization boundary

The planned customer Entertainment area will play OMISHA-created or explicitly licensed content. It will not scrape or re-host Instagram/YouTube reels. A social account login is not permission to use the account's posts commercially. Host each video once in the OMISHA media tier and store a single content record with rights, territory, age rating, moderation and expiry metadata.

The first revenue option is an OMISHA-owned publisher/payee account with AdMob and optional direct sponsorship. Use test ads during development. Rewarded ads are voluntary and limited to non-essential game rewards; they never gate internet access, payments, support or regulatory functions. For any meaningful game reward, the backend must verify AdMob server-side callbacks and deduplicate each reward before posting it to an entertainment-only ledger. No AdMob SDK, production ad unit, game/reel catalog or rewards ledger is included yet. Do not store subscriber PII or identity evidence in ad analytics.

## Build

The local inspection environment did not have Flutter or Dart. After those tools are installed in a developer/build environment, generate the Android host project, configure app IDs/OAuth fingerprints and then resolve dependencies. Do not publish an APK until the Go auth endpoints and app privacy/identity provider configuration are live and reviewed.
