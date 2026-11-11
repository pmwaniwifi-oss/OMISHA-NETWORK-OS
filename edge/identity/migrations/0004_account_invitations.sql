-- Server-side invitation records for admin-led enrollment.
-- Raw invitation tokens are returned once to the caller and are never stored.
BEGIN;

CREATE UNIQUE INDEX memberships_membership_identity_uq
    ON memberships(membership_id, identity_id);

CREATE TABLE account_invitations (
    invitation_id UUID PRIMARY KEY,
    token_hmac BYTEA NOT NULL UNIQUE CHECK (octet_length(token_hmac) = 32),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id) ON DELETE RESTRICT,
    issuer_identity_id UUID NOT NULL REFERENCES identities(identity_id) ON DELETE RESTRICT,
    issuer_membership_id UUID NOT NULL,
    recipient_email_hmac BYTEA CHECK (
        recipient_email_hmac IS NULL OR octet_length(recipient_email_hmac) = 32
    ),
    role_code TEXT NOT NULL CHECK (length(role_code) BETWEEN 1 AND 64),
    scope_json JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(scope_json) = 'object'),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'redeemed', 'revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    redeemed_by_identity_id UUID,
    redeemed_membership_id UUID,
    redeemed_at TIMESTAMPTZ,
    revoked_by_identity_id UUID REFERENCES identities(identity_id) ON DELETE RESTRICT,
    revoked_at TIMESTAMPTZ,
    CHECK (expires_at > created_at),
    CHECK (
        (status = 'pending' AND redeemed_by_identity_id IS NULL
            AND redeemed_membership_id IS NULL AND redeemed_at IS NULL AND revoked_at IS NULL)
        OR
        (status = 'redeemed' AND redeemed_by_identity_id IS NOT NULL
            AND redeemed_membership_id IS NOT NULL AND redeemed_at IS NOT NULL AND revoked_at IS NULL)
        OR
        (status = 'revoked' AND redeemed_by_identity_id IS NULL
            AND redeemed_membership_id IS NULL AND redeemed_at IS NULL AND revoked_at IS NOT NULL)
    ),
    FOREIGN KEY (issuer_membership_id, issuer_identity_id)
        REFERENCES memberships(membership_id, identity_id) ON DELETE RESTRICT,
    FOREIGN KEY (redeemed_membership_id, redeemed_by_identity_id)
        REFERENCES memberships(membership_id, identity_id) ON DELETE RESTRICT
);

CREATE INDEX account_invitations_issuer_created_idx
    ON account_invitations(issuer_identity_id, created_at DESC);
CREATE INDEX account_invitations_org_pending_idx
    ON account_invitations(organization_id, expires_at)
    WHERE status = 'pending';

INSERT INTO omisha_schema_migrations (version) VALUES ('0004_account_invitations');

COMMIT;
