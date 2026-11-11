-- Add token-family tracking so logout revokes one device login and its scoped sessions.
BEGIN;

ALTER TABLE sessions ADD COLUMN session_family_id UUID;
UPDATE sessions SET session_family_id = session_id WHERE session_family_id IS NULL;
ALTER TABLE sessions ALTER COLUMN session_family_id SET NOT NULL;

CREATE INDEX sessions_family_live_idx
    ON sessions(session_family_id, expires_at) WHERE revoked_at IS NULL;

INSERT INTO omisha_schema_migrations (version) VALUES ('0003_session_families');

COMMIT;
