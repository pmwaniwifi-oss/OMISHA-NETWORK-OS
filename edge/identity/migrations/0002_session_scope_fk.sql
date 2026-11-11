-- Ensure a context session cannot combine an identity, membership and organization
-- that do not belong together. This is safe to apply after 0001.
BEGIN;

CREATE UNIQUE INDEX memberships_session_scope_uq
    ON memberships(membership_id, identity_id, organization_id);

ALTER TABLE sessions
    ADD CONSTRAINT sessions_membership_scope_fk
    FOREIGN KEY (membership_id, identity_id, organization_id)
    REFERENCES memberships(membership_id, identity_id, organization_id)
    ON DELETE RESTRICT;

INSERT INTO omisha_schema_migrations (version) VALUES ('0002_session_scope_fk');

COMMIT;
