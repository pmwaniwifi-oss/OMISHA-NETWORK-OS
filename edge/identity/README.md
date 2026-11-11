# Identity control-plane

This directory contains the identity-only PostgreSQL schema, deployment overlay and Go gateway identity endpoints. Google challenge/token exchange, approved workspace discovery, context activation, scoped sessions, current-context lookup and per-device-family logout are implemented in source. Migration 0004 adds HMAC-only invitation storage. Go source adds `POST /v1/omisha/isps`, `POST /v1/me/invitations`, and `POST /v1/auth/invitations/redeem` with UUIDv4 request idempotency, scoped issuer checks, role allowlists, expiry, single-use redemption and audit rows. These APIs are not build/integration validated. Android deep-link/share UI, branded link delivery, recipient-email binding, initial OMISHA-admin bootstrap, self-care payment, Aadhaar verification and business APIs remain unimplemented. Nothing here is build- or integration-validated and it does not enable business operations.

## Scope

The schema stores internal identities, pseudonymous external provider subjects, organizations, approved memberships, HMAC-hashed sessions, short-lived challenge nonce fingerprints, HMAC-only account invitation records, and minimized security audit events. It must not hold subscriber profiles, billing/accounting rows, Aadhaar artifacts, raw invitation tokens, OAuth ID/access tokens, passwords, or tenant business records.

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

The gateway now implements `POST /v1/auth/social/google/challenge` and `POST /v1/auth/social/google`. It validates Google token signature/issuer/audience/expiry, checks the exact nonce claim, consumes the short-lived challenge transactionally, HMAC-pseudonymizes the provider subject, and stores only a digest of a short-lived opaque identity session. The code returns 503 until its database URL, HMAC key and Google server client ID are configured. OTP/password login is intentionally excluded. Customer invite redemption creates a pending membership; payment/verification activation is a separate missing workflow. Tenant credential routing and business endpoints are not implemented. An identity without an approved active membership receives no workspace context. Context APIs return display labels and empty capabilities; no business authorization is implied. Do not expose customer/staff workflows until native/mobile integration, membership provisioning, role mapping and cross-tenant/role-escalation tests are complete.
