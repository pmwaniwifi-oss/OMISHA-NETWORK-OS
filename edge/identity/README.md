# Identity control-plane

This directory contains the identity-only PostgreSQL schema, deployment overlay and Go gateway's first Google sign-in endpoints. Google challenge issuance and identity-session creation are implemented in source, but workspace membership discovery, context activation, logout/revocation and business API authorization are not yet complete; therefore this is not a usable end-to-end login.

## Scope

The schema stores internal identities, pseudonymous external provider subjects, organizations, approved memberships, HMAC-hashed sessions, short-lived authentication challenge nonce fingerprints, and minimized security audit events. It must not hold subscriber profiles, billing/accounting rows, Aadhaar artifacts, OAuth ID/access tokens, passwords, or tenant business records.

Each ISP tenant keeps its own business database boundary. The control-plane database is a deliberately small directory needed to resolve the user's authorized workspace contexts.

## Secret handling

- Generate random UUIDs in the application.
- Compute `subject_hmac` as HMAC-SHA-256 over provider + provider subject with a server-held key; never store the raw provider subject.
- Store only HMAC-SHA-256 digests of high-entropy opaque session tokens. Never use a plain hash for low-entropy OTPs.
- `nonce_hmac` is the keyed fingerprint of a server-issued, one-use authentication challenge nonce. Never store the raw nonce or provider ID token in this table. Consume the challenge atomically after signature, audience, issuer, expiry and nonce validation.
- Keep HMAC keys, DB credentials and encryption keys in the deployment secret manager/runtime secret mounts, never in Git or Compose defaults.

## Apply and evolve

Migrations are ordered, append-only SQL. Apply through a migration runner with a dedicated schema-owner credential; the runtime gateway account should have only the minimum required SELECT/INSERT/UPDATE permissions. Take a tested backup before a migration and verify restore in a non-production environment. Do not edit an applied migration: add a new numbered migration.

Google ID tokens are bearer credentials and can remain valid until expiry; do not mark a whole ID token globally one-use because legitimate retries and another signed-in device may present it again. Replay protection requires a fresh server challenge nonce bound into the provider authentication request. The Flutter shell uses a native Android Credential Manager bridge and supplies a fresh challenge nonce for each attempt. The challenge and token routes exist in the Go gateway. The native bridge and Go integration have not yet been built/validated together.

The Compose overlay keeps PostgreSQL on an internal-only network and adds only the gateway to that network. It publishes no DB port. Use the separate runtime role created at initial database bootstrap, then apply migrations and explicit grants with `bash edge/identity/apply-migrations.sh`. Keep the volume on encrypted storage and back it up.

## Important authorization constraint

A membership row is not authorization by itself. Every context activation must re-read live identity, membership, organization and expiry state. Every business API request must check the scoped session and enforce resource ownership/assignment. Client-supplied role, organization, database name or connection string must never select privileges or tenant databases.

The gateway now implements `POST /v1/auth/social/google/challenge` and `POST /v1/auth/social/google`. It validates Google token signature/issuer/audience/expiry, checks the exact nonce claim, consumes the short-lived challenge transactionally, HMAC-pseudonymizes the provider subject, and stores only a digest of a short-lived opaque identity session. The code returns 503 until its database URL, HMAC key and Google server client ID are configured. OTP delivery/verification, context listing/activation, session revocation, tenant credential routing and business endpoints still return 501; do not expose customer/staff workflows until those controls and cross-tenant/role-escalation tests are complete.
