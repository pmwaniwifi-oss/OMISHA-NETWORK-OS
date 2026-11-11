-- OMISHA identity-control-plane schema, migration 0001.
-- This database stores identity references and memberships only; never ISP business data.
-- Application supplies UUIDs and HMAC-SHA-256 pseudonyms using a server-held key.
BEGIN;

CREATE TABLE IF NOT EXISTS omisha_schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE identities (
    identity_id UUID PRIMARY KEY,
    status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE external_identities (
    provider TEXT NOT NULL CHECK (provider IN ('google', 'email_otp', 'phone_otp')),
    subject_hmac BYTEA NOT NULL CHECK (octet_length(subject_hmac) = 32),
    identity_id UUID NOT NULL REFERENCES identities(identity_id) ON DELETE RESTRICT,
    verified_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject_hmac),
    UNIQUE (identity_id, provider)
);

CREATE TABLE organizations (
    organization_id UUID PRIMARY KEY,
    organization_type TEXT NOT NULL CHECK (
        organization_type IN ('isp_tenant', 'omisha_workspace')
    ),
    display_label TEXT NOT NULL CHECK (length(display_label) BETWEEN 1 AND 120),
    status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
    membership_id UUID PRIMARY KEY,
    identity_id UUID NOT NULL REFERENCES identities(identity_id) ON DELETE RESTRICT,
    organization_id UUID NOT NULL REFERENCES organizations(organization_id) ON DELETE RESTRICT,
    role_code TEXT NOT NULL CHECK (length(role_code) BETWEEN 1 AND 64),
    scope_json JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(scope_json) = 'object'),
    status TEXT NOT NULL CHECK (status IN ('invited', 'active', 'suspended', 'revoked')),
    approved_by UUID REFERENCES identities(identity_id) ON DELETE RESTRICT,
    approved_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (identity_id, organization_id, role_code),
    CHECK ((status <> 'active') OR approved_at IS NOT NULL)
);

CREATE INDEX memberships_identity_status_idx
    ON memberships(identity_id, status, organization_id);

CREATE TABLE sessions (
    session_id UUID PRIMARY KEY,
    identity_id UUID NOT NULL REFERENCES identities(identity_id) ON DELETE RESTRICT,
    token_hmac BYTEA NOT NULL UNIQUE CHECK (octet_length(token_hmac) = 32),
    session_kind TEXT NOT NULL CHECK (session_kind IN ('identity', 'context')),
    organization_id UUID REFERENCES organizations(organization_id) ON DELETE RESTRICT,
    membership_id UUID REFERENCES memberships(membership_id) ON DELETE RESTRICT,
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    CHECK (expires_at > issued_at),
    CHECK (
        (session_kind = 'identity' AND organization_id IS NULL AND membership_id IS NULL)
        OR
        (session_kind = 'context' AND organization_id IS NOT NULL AND membership_id IS NOT NULL)
    )
);

CREATE INDEX sessions_identity_live_idx
    ON sessions(identity_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE auth_challenge_nonces (
    challenge_id UUID PRIMARY KEY,
    provider TEXT NOT NULL CHECK (provider IN ('google')),
    nonce_hmac BYTEA NOT NULL CHECK (octet_length(nonce_hmac) = 32),
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    UNIQUE (provider, nonce_hmac),
    CHECK (expires_at > issued_at)
);

CREATE INDEX auth_challenge_nonces_live_idx
    ON auth_challenge_nonces(provider, expires_at) WHERE consumed_at IS NULL;

CREATE TABLE security_audit_events (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_identity_id UUID REFERENCES identities(identity_id) ON DELETE RESTRICT,
    organization_id UUID REFERENCES organizations(organization_id) ON DELETE RESTRICT,
    event_code TEXT NOT NULL CHECK (length(event_code) BETWEEN 1 AND 80),
    outcome TEXT NOT NULL CHECK (outcome IN ('success', 'denied', 'error')),
    correlation_id UUID,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX security_audit_events_time_idx ON security_audit_events(occurred_at);
CREATE INDEX security_audit_events_actor_idx
    ON security_audit_events(actor_identity_id, occurred_at);

INSERT INTO omisha_schema_migrations (version) VALUES ('0001_identity');

COMMIT;
