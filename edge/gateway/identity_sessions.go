package main

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
)

const contextSessionLifetime = 12 * time.Hour

type sessionPrincipal struct {
	SessionID       string
	IdentityID      string
	FamilyID        string
	Kind            string
	OrganizationID  sql.NullString
	MembershipID    sql.NullString
}

type workspaceContextResponse struct {
	ContextID       string   `json:"context_id"`
	Organization    string   `json:"organization_name"`
	WorkspaceType   string   `json:"workspace_type"`
	Capabilities    []string `json:"capabilities"`
	RoleLabels      []string `json:"role_labels"`
}

func (api *googleIdentityAPI) listMyContexts(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	principal, err := api.authenticateSession(ctx, r, "identity")
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	rows, err := api.db.QueryContext(ctx,
		`SELECT m.membership_id::text, o.display_label, o.organization_type, m.role_code
		 FROM memberships m
		 JOIN identities i ON i.identity_id = m.identity_id
		 JOIN organizations o ON o.organization_id = m.organization_id
		 WHERE m.identity_id = $1 AND i.status = 'active'
		   AND m.status = 'active' AND m.approved_at IS NOT NULL
		   AND o.status = 'active' AND (m.expires_at IS NULL OR m.expires_at > now())
		 ORDER BY o.display_label, m.role_code`, principal.IdentityID)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account list unavailable"})
		return
	}
	defer rows.Close()
	contexts := make([]workspaceContextResponse, 0, 4)
	for rows.Next() {
		var item workspaceContextResponse
		var role string
		if err := rows.Scan(&item.ContextID, &item.Organization, &item.WorkspaceType, &role); err != nil {
			writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account list unavailable"})
			return
		}
		// Roles are display labels only. Authorization is enforced by server-side membership checks.
		item.RoleLabels = []string{role}
		item.Capabilities = []string{}
		contexts = append(contexts, item)
		if len(contexts) > 50 {
			writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account list unavailable"})
			return
		}
	}
	if rows.Err() != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account list unavailable"})
		return
	}
	writeAuthJSON(w, http.StatusOK, map[string]any{"contexts": contexts})
}

type activateContextRequest struct {
	ContextID string `json:"context_id"`
}

func (api *googleIdentityAPI) activateMyContext(w http.ResponseWriter, r *http.Request) {
	var body activateContextRequest
	if err := decodeStrictJSON(w, r, &body, 2048); err != nil || !challengeIDPattern.MatchString(body.ContextID) {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid context request"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	tx, err := api.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account activation unavailable"})
		return
	}
	defer tx.Rollback()
	principal, err := api.authenticateSessionTx(ctx, tx, r, "identity")
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	var organizationID, organizationLabel, organizationType, role string
	err = tx.QueryRowContext(ctx,
		`SELECT o.organization_id::text, o.display_label, o.organization_type, m.role_code
		 FROM memberships m JOIN identities i ON i.identity_id = m.identity_id
		 JOIN organizations o ON o.organization_id = m.organization_id
		 WHERE m.membership_id = $1 AND m.identity_id = $2
		   AND i.status = 'active' AND m.status = 'active' AND m.approved_at IS NOT NULL
		   AND o.status = 'active' AND (m.expires_at IS NULL OR m.expires_at > now())`,
		body.ContextID, principal.IdentityID).Scan(&organizationID, &organizationLabel, &organizationType, &role)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeAuthJSON(w, http.StatusForbidden, map[string]string{"error": "account access is unavailable"})
		} else {
			writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account activation unavailable"})
		}
		return
	}
	sessionID, err := randomUUID()
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account activation unavailable"})
		return
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account activation unavailable"})
		return
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	expiresAt := time.Now().UTC().Add(contextSessionLifetime)
	_, err = tx.ExecContext(ctx,
		`INSERT INTO sessions
		 (session_id, identity_id, token_hmac, session_kind, organization_id, membership_id,
		  session_family_id, issued_at, expires_at)
		 VALUES ($1, $2, $3, 'context', $4, $5, $6, now(), $7)`,
		sessionID, principal.IdentityID, keyedDigest(api.hmacKey, "session-token", token),
		organizationID, body.ContextID, principal.FamilyID, expiresAt)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account activation unavailable"})
		return
	}
	if err := insertSecurityAudit(ctx, tx, principal.IdentityID, "auth.context.activate", "success"); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account activation unavailable"})
		return
	}
	if err := tx.Commit(); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "account activation unavailable"})
		return
	}
	writeAuthJSON(w, http.StatusOK, map[string]any{
		"access_token": token,
		"expires_at": expiresAt.Format(time.RFC3339),
		"active_context": workspaceContextResponse{
			ContextID: body.ContextID, Organization: organizationLabel,
			WorkspaceType: organizationType, RoleLabels: []string{role},
			Capabilities: []string{},
		},
	})
}

func (api *googleIdentityAPI) currentContext(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	principal, err := api.authenticateSession(ctx, r, "context")
	if err != nil || !principal.OrganizationID.Valid || !principal.MembershipID.Valid {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	var response workspaceContextResponse
	var role string
	err = api.db.QueryRowContext(ctx,
		`SELECT m.membership_id::text, o.display_label, o.organization_type, m.role_code
		 FROM sessions s JOIN identities i ON i.identity_id = s.identity_id
		 JOIN memberships m ON m.membership_id = s.membership_id AND m.identity_id = s.identity_id
		 JOIN organizations o ON o.organization_id = s.organization_id
		 WHERE s.session_id = $1 AND i.status = 'active'
		   AND m.status = 'active' AND m.approved_at IS NOT NULL
		   AND o.status = 'active' AND (m.expires_at IS NULL OR m.expires_at > now())`,
		principal.SessionID).Scan(&response.ContextID, &response.Organization, &response.WorkspaceType, &role)
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "account access is unavailable"})
		return
	}
	response.RoleLabels = []string{role}
	response.Capabilities = []string{}
	writeAuthJSON(w, http.StatusOK, map[string]any{"active_context": response})
}

func (api *googleIdentityAPI) logoutSessionFamily(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	principal, err := api.authenticateSession(ctx, r, "")
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	_, err = api.db.ExecContext(ctx,
		`UPDATE sessions SET revoked_at = now()
		 WHERE session_family_id = $1 AND revoked_at IS NULL`, principal.FamilyID)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "logout unavailable"})
		return
	}
	_ = api.db.ExecContext(ctx,
		`INSERT INTO security_audit_events (actor_identity_id, event_code, outcome)
		 VALUES ($1, 'auth.logout', 'success')`, principal.IdentityID)
	writeAuthJSON(w, http.StatusOK, map[string]bool{"logged_out": true})
}

func (api *googleIdentityAPI) authenticateSession(ctx context.Context, r *http.Request, requiredKind string) (sessionPrincipal, error) {
	return api.authenticateSessionWith(ctx, api.db, r, requiredKind)
}

func (api *googleIdentityAPI) authenticateSessionTx(ctx context.Context, tx *sql.Tx, r *http.Request, requiredKind string) (sessionPrincipal, error) {
	return api.authenticateSessionWith(ctx, tx, r, requiredKind)
}

type sessionQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func (api *googleIdentityAPI) authenticateSessionWith(ctx context.Context, q sessionQueryer, r *http.Request, requiredKind string) (sessionPrincipal, error) {
	var principal sessionPrincipal
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		return principal, errors.New("missing bearer")
	}
	token := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
	if len(token) < 32 || len(token) > 256 {
		return principal, errors.New("invalid bearer")
	}
	err := q.QueryRowContext(ctx,
		`SELECT s.session_id::text, s.identity_id::text, s.session_family_id::text,
		        s.session_kind, s.organization_id::text, s.membership_id::text
		 FROM sessions s JOIN identities i ON i.identity_id = s.identity_id
		 WHERE s.token_hmac = $1 AND s.revoked_at IS NULL AND s.expires_at > now()
		   AND i.status = 'active'`,
		keyedDigest(api.hmacKey, "session-token", token)).Scan(
		&principal.SessionID, &principal.IdentityID, &principal.FamilyID,
		&principal.Kind, &principal.OrganizationID, &principal.MembershipID)
	if err != nil || (requiredKind != "" && principal.Kind != requiredKind) {
		return sessionPrincipal{}, errors.New("invalid or expired session")
	}
	return principal, nil
}

func decodeStrictJSON(w http.ResponseWriter, r *http.Request, target any, maxBytes int64) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err == nil {
		return errors.New("extra JSON value")
	}
	return nil
}

// Indirection keeps callers independent from crypto/rand in this file's public API.
var cryptoRandomRead = func(buffer []byte) (int, error) {
	return cryptoRandRead(buffer)
}
