# OMISHA NETWORK OS Android app shell

One Flutter Android app package serves customer, ISP organization, and OMISHA workforce users. The login screen does not ask users to grant themselves roles. After authentication, the backend returns the memberships and capabilities the account is allowed to use.

## Current source

- `lib/main.dart`: single sign-in shell, server-returned workspace picker, capability display, workspace switching, and logout.
- `lib/api.dart`: HTTPS-only API client contract with bounded responses and separate identity/context-scoped tokens.
- `flutter_secure_storage`: stores the tokens in platform secure storage. The package currently uses Android's secure cryptographic storage; validate device/backup behavior during Android release hardening.
- The Android platform project has not yet been generated. This is a Flutter package source shell, not a signed/build-ready APK.

## Backend API contract required

The Go API/BFF must implement and secure these routes before login can work:

1. `POST /v1/auth/challenges` with `identifier`; return a generic `challenge_id` response that does not reveal whether an account exists. The backend decides the allowed verification channel.
2. `POST /v1/auth/challenges/verify` with challenge ID and code; return a short-lived `identity_token`. This token may enumerate only memberships and activate an authorized context; it must not authorize customer, ISP, or platform business data.
3. `GET /v1/me/contexts` with the identity token; return server-authorized `context_id`, organization/workspace labels, role labels and display capabilities.
4. `POST /v1/me/contexts/activate` with a context ID returned by step 3; server revalidates membership and returns a short-lived tenant/workspace-scoped `access_token` plus its active context.
5. `GET /v1/me` with the scoped access token; return only the active workspace profile and capability display data.
6. `POST /v1/auth/logout`; revoke the scoped token and associated identity session/token family.

Every business endpoint must independently enforce user, role, tenant and record assignment. Hiding a screen in Flutter is not authorization. A request body cannot select a tenant, role, or capability. Customer, ISP staff, OMISHA workforce, and platform administration must have separate authorization scopes; platform or cross-tenant access is denied by default.

## Session handling

The app stores the short-lived identity token and active context access token in secure storage, never SharedPreferences. Context listing/switching uses only the membership token; customer/ISP/OMISHA business requests must use the server-issued context-scoped token. Logout clears both local tokens even if server revocation is temporarily unavailable. Expired sessions return the user to sign-in; no refresh-token flow is implemented.

Role/workspace metadata is display-only. Do not store subscriber lists, Aadhaar artifacts, payment credentials, or sensitive offline work in this shell. Offline mode is not implemented.

## Build after Flutter tooling is available

From this directory:

```sh
flutter create --platforms=android --org com.omisha .
flutter pub get
flutter build apk --dart-define=OMISHA_API_BASE_URL=https://api.example.invalid/
```

Replace the example HTTPS URL only after the Go API is deployed with TLS and the identity/context endpoints above. Do not point the app at a live system until API authorization, session revocation, tenant isolation, account recovery, and cross-role access controls have been reviewed.

## Verification state

Flutter and Dart SDK were not present in the inspected workspace, so this source package has not been compiled or run. The Go endpoints above are a contract only and are not implemented by the current gateway. A production login, role workspace, mobile onboarding, or Android APK is not yet available.
