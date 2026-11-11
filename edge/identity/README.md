# Identity control-plane schema

This directory defines the first identity-only database migration for OMISHA-NETWORK-OS. It is not an operational login service.

## Scope

The schema stores internal identities, pseudonymous external provider subjects, organizations, approved memberships, hashed sessions, short-lived replay fingerprints, and minimized security audit events. It must not hold subscriber profiles, billing/accounting rows, Aadhaar artifacts, OAuth ID/access tokens, passwords, or tenant business records.

Each ISP tenant keeps its own business database boundary. The control-plane database is a deliberately small directory needed to resolve the user's authorized workspace contexts.

## Secret handling

- Generate random UUIDs in the application.
- Compute `subject_hmac` as HMAC-SHA-256 over provider + provider subject with a server-held key; never store the raw provider subject.
- Store only HMAC-SHA-256 digests of high-entropy opaque session tokens. Never use a plain hash for low-entropy OTPs.
- `token_fingerprint` is a keyed fingerprint of the provider ID token, kept only through the token expiry window to reject replay. Do not persist the token itself.
- Keep HMAC keys, DB credentials and encryption keys in the deployment secret manager/runtime secret mounts, never in Git or Compose defaults.

## Apply and evolve

Migrations are ordered, append-only SQL. Apply through a migration runner with a dedicated schema-owner credential; the runtime gateway account should have only the minimum required SELECT/INSERT/UPDATE permissions. Take a tested backup before a migration and verify restore in a non-production environment. Do not edit an applied migration: add a new numbered migration.

The first deployment must create the database on an internal-only network, encrypted persistent storage, restricted database role, backup schedule and retention policy before adding an API route. No public DB port is needed.

## Important authorization constraint

A membership row is not authorization by itself. Every context activation must re-read live identity, membership, organization and expiry state. Every business API request must check the scoped session and enforce resource ownership/assignment. Client-supplied role, organization, database name or connection string must never select privileges or tenant databases.

The current gateway still returns HTTP 501 for `/v1/*`. Google token validation, OTP verification, session issuance/revocation, membership provisioning, tenant credential resolution and authorization middleware are not implemented. Do not enable login until those controls and cross-tenant/role-escalation tests exist.
