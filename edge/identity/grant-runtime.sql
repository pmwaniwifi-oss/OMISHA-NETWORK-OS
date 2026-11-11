-- Apply only after the identity migrations, as the database owner.
-- Deliberately omit DELETE, DDL, and broad default privileges from the gateway role.
GRANT USAGE ON SCHEMA public TO omisha_identity_runtime;
GRANT SELECT, INSERT ON identities, external_identities TO omisha_identity_runtime;
GRANT INSERT ON organizations, memberships TO omisha_identity_runtime;
GRANT SELECT, INSERT, UPDATE ON auth_challenge_nonces TO omisha_identity_runtime;
GRANT SELECT, INSERT, UPDATE ON sessions TO omisha_identity_runtime;
GRANT SELECT ON organizations, memberships TO omisha_identity_runtime;
GRANT SELECT, INSERT, UPDATE ON account_invitations TO omisha_identity_runtime;
GRANT INSERT ON security_audit_events TO omisha_identity_runtime;
GRANT USAGE, SELECT ON SEQUENCE security_audit_events_audit_id_seq TO omisha_identity_runtime;
