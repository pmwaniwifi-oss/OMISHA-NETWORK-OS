# OMISHA NETWORK OS Android app shell

One Flutter Android app package serves customer, ISP organization, and OMISHA workforce users. The login screen does not ask users to grant themselves roles. After authentication, the backend returns the memberships and capabilities the account is allowed to use.

## Current source

- `lib/main.dart`: single sign-in shell, server-returned workspace picker, capability display, workspace switching, and logout.
- `lib/api.dart`: HTTPS-only API client contract with bounded responses and separate identity/context-scoped tokens.
- `flutter_secure_storage`: stores the tokens in platform secure storage. The package currently uses Android's secure cryptographic storage; validate device/backup behavior during Android release hardening.
- `android-host/MainActivity.java` is a small native bridge to Android Credential Manager. The CI workflow generates the Flutter host, copies this bridge, and adds stable AndroidX Credential Manager 1.6.0 plus Google ID 1.2.0 dependencies. Android minSdk is 23. This is still source scaffolding, not a signed/build-ready release.

## Backend API contract

Google is the only user sign-in provider for customer, ISP and OMISHA staff accounts. There is no OTP, password, or separate role-specific login path in the Android app.

1. `POST /v1/auth/social/google/challenge` with no user-supplied identity. Return a short-lived `challenge_id` and cryptographically random `nonce`; store only its server-keyed fingerprint.
2. `POST /v1/auth/social/google` with `challenge_id`, nonce and Google `id_token`. Validate Google's signature, issuer, expected server client ID, expiry and exact nonce claim; atomically consume the matching challenge before issuing an OMISHA identity session.
3. `GET /v1/me/contexts` with the identity token; return only approved active memberships.
4. `POST /v1/me/contexts/activate` with a returned context ID; revalidate live membership and return a scoped access token.
5. `GET /v1/me` with the scoped token; revalidate active membership and return the active workspace.
6. `POST /v1/auth/logout`; revoke the identity session and all scoped sessions in that device's session family.

Google proves account identity; it does not prove that the person is an ISP subscriber, employee, technician or administrator. OMISHA/ISP-approved membership provisioning assigns those workspaces. The app never allows users to grant themselves roles. Every business endpoint must independently enforce tenant, role and record assignment.

## Enrollment and role assignment

- OMISHA admin creates an ISP organization and issues the first ISP owner/admin invitation.
- An authorized ISP admin issues ISP-bound staff/customer invitations. The invitation record fixes the allowed organization, role/scope, expiry and recipient restriction; the link cannot grant a role by changing URL parameters.
- An end customer may also start in self-care without an invite. Serviceability, applicable identity checks and a server-verified/reconciled payment must pass before paid service onboarding is finalized.
- Every invite recipient signs in with Google. Offline Aadhaar verification is a separate identity-proof step only if the operator confirms the legal basis, approved method, consent/alternatives and OVSE applicability. Aadhaar is never a login provider and raw Aadhaar files must not be retained in normal app storage.
- Google identity alone creates no ISP, staff, customer-paid or admin entitlement. The server redeems the invitation once and creates the approved membership; all such flows are still planned and have no implementation/API yet.

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

Flutter and Dart SDK were not present in the inspected workspace, so this source package has not been compiled or run. The Go Google challenge/token and workspace/session endpoints exist in source but have not been build/integration validated. Membership provisioning, OTP/password login, tenant routing and business APIs are not implemented; no production login, role workspace or signed Android release is available.


## Google social sign-in

The Flutter UI calls a native Android Credential Manager bridge for Google sign-in. Each attempt first fetches a fresh challenge and passes its nonce to the Credential Manager Google ID-token request. Configure `OMISHA_GOOGLE_SERVER_CLIENT_ID` at build time with the server/web OAuth client ID created in OMISHA's Google Cloud project. Also register the final Android application ID and signing certificate fingerprints there. Do not put a client secret in the app or repository.

The app sends the Google ID token plus `challenge_id` to `POST /v1/auth/social/google`; the Go backend must verify token signature, issuer, audience, expiry and exact nonce claim against Google's current keys, then consume the challenge atomically. Use Google's stable subject as the provider identity. Do not accept client-supplied role/tenant data, auto-link accounts solely by a typed email, or grant employee/ISP roles from Google sign-in. Staff and ISP memberships require server-side invitation/approval; customer service still requires the applicable contact/subscriber checks. Request no Google data-access scopes beyond basic sign-in.

The Go gateway now has Google challenge and token-exchange routes that validate the ID token, require the returned nonce to match the challenge, consume the challenge once, and issue an opaque identity session. These routes require the identity Compose overlay, applied migrations/runtime grants, `OMISHA_GOOGLE_SERVER_CLIENT_ID`, and secret files. The native bridge and Go integration have not yet been validated in an Android build. Membership/context endpoints and OTP delivery/verification remain unimplemented, so a complete customer or staff login is not operational.

## Games, reels, and monetization boundary

The planned customer Entertainment area will play OMISHA-created or explicitly licensed content. It will not scrape or re-host Instagram/YouTube reels. A social account login is not permission to use the account's posts commercially. Host each video once in the OMISHA media tier and store a single content record with rights, territory, age rating, moderation and expiry metadata.

The first revenue option is an OMISHA-owned publisher/payee account with AdMob and optional direct sponsorship. Use test ads during development. Rewarded ads are voluntary and limited to non-essential game rewards; they never gate internet access, payments, support or regulatory functions. For any meaningful game reward, the backend must verify AdMob server-side callbacks and deduplicate each reward before posting it to an entertainment-only ledger. No AdMob SDK, production ad unit, game/reel catalog or rewards ledger is included yet. Do not store subscriber PII or identity evidence in ad analytics.

## Build

The local inspection environment did not have Flutter or Dart. After those tools are installed in a developer/build environment, generate the Android host project, configure app IDs/OAuth fingerprints and then resolve dependencies. Do not publish an APK until the Go auth endpoints and app privacy/identity provider configuration are live and reviewed.
