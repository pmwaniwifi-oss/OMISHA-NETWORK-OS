# Identity control-plane schema

This directory defines the first identity-only database migration for OMISHA-NETWORK-OS. It is not an operational login service.

## Scope

The schema stores internal identities, pseudonymous external provider subjects, organizations, approved memberships, hashed sessions, short-lived replay fingerprints, and minimized security audit events. It must not hold subscriber profiles, billing/accounting rows, Aadhaar artifacts, OAuth ID/access tokens, passwords, or tenant business records.

Each ISP tenant keeps its own business database boundary. The control-plane database is a deliberately small directory needed to resolve the user's authorized workspace contexts.

## Secret handling

- Generate random UUIDs in the application.
- Compute `subject_hmac` as HMAC-SHA-256 over provider + provider subject with a server-held key; never store the raw provider subject.
- Store only HMAC-SHA-256 digests of high-entropy opaque session tokens. Never use a plain hash for low-entropy OTPs.
- `nonce_hmac` is the keyed fingerprint of a server-issued, one-use authentication challenge nonce. Never store the raw nonce or provider ID token in this table. Consume the challenge atomically after signature, audience, issuer, expiry and nonce validation.
- Keep HMAC keys, DB credentials and encryption keys in the deployment secret manager/runtime secret mounts, never in Git or Compose defaults.

## Apply and evolve

Migrations are ordered, append-only SQL. Apply through a migration runner with a dedicated schema-owner credential; the runtime gateway account should have only the minimum required SELECT/INSERT/UPDATE permissions. Take a tested backup before a migration and verify restore in a non-production environment. Do not edit an applied migration: add a new numbered migration.

Google ID tokens are bearer credentials and can remain valid until expiry; do not mark a whole ID token globally one-use because legitimate retries and another signed-in device may present it again. Replay protection requires a fresh server challenge nonce bound into the provider authentication request. The current Flutter shell initializes google_sign_in once without a nonce; its provider flow must be upgraded or replaced before production login. The google_sign_in singleton requires initialization exactly once, so a per-attempt nonce cannot simply be passed by reinitializing it for every login.

The first deployment must create the database on an internal-only network, encrypted persistent storage, restricted database role, backup schedule and retention policy before adding an API route. No public DB port is needed.

## Important authorization constraint

A membership row is not authorization by itself. Every context activation must re-read live identity, membership, organization and expiry state. Every business API request must check the scoped session and enforce resource ownership/assignment. Client-supplied role, organization, database name or connection string must never select privileges or tenant databases.

The current gateway still returns HTTP 501 for `/v1/*`. Google token validation, OTP verification, session issuance/revocation, membership provisioning, tenant credential resolution and authorization middleware are not implemented. Do not enable login until those controls and cross-tenant/role-escalation tests exist.
