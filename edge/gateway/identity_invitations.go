package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	invitationDefaultLifetime = 72 * time.Hour
	invitationMaximumLifetime = 7 * 24 * time.Hour
)

type invitationRequest struct {
	RoleCode       string `json:"role_code"`
	ExpiresInHours int    `json:"expires_in_hours"`
}

type createISPRequest struct {
	DisplayLabel string `json:"display_label"`
}

type invitationRow struct {
	ID             string
	OrganizationID string
	OrganizationType string
	DisplayLabel   string
	RoleCode       string
	Status         string
	ExpiresAt      time.Time
	RedeemedMembershipID sql.NullString
}

func (api *googleIdentityAPI) createISPAndOwnerInvitation(w http.ResponseWriter, r *http.Request) {
	var body createISPRequest
	if err := decodeStrictJSON(w, r, &body, 4096); err != nil || strings.TrimSpace(body.DisplayLabel) == "" || len([]rune(strings.TrimSpace(body.DisplayLabel))) > 120 {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid ISP registration request"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	tx, err := api.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "ISP registration unavailable"})
		return
	}
	defer tx.Rollback()
	principal, err := api.authenticateSessionTx(ctx, tx, r, "context")
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	role, orgType, err := activeContextRole(ctx, tx, principal)
	if err != nil || orgType != "omisha_workspace" || role != "omisha.platform_admin" {
		writeAuthJSON(w, http.StatusForbidden, map[string]string{"error": "OMISHA administrator access required"})
		return
	}
	organizationID, err := randomUUID()
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "ISP registration unavailable"})
		return
	}
	label := strings.TrimSpace(body.DisplayLabel)
	if _, err = tx.ExecContext(ctx,
		`INSERT INTO organizations (organization_id, organization_type, display_label, status)
		 VALUES ($1, 'isp_tenant', $2, 'active')`, organizationID, label); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "ISP registration unavailable"})
		return
	}
	invite, token, err := api.insertInvitation(ctx, tx, principal, organizationID, "isp.owner", invitationDefaultLifetime)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "ISP invitation could not be created"})
		return
	}
	if err := insertEnrollmentAudit(ctx, tx, principal.IdentityID, organizationID, "enrollment.isp.created", "success"); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "ISP registration unavailable"})
		return
	}
	if err := tx.Commit(); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "ISP registration unavailable"})
		return
	}
	writeInvitationResponse(w, invite, token)
}

func (api *googleIdentityAPI) createWorkspaceInvitation(w http.ResponseWriter, r *http.Request) {
	var body invitationRequest
	if err := decodeStrictJSON(w, r, &body, 4096); err != nil || !validRoleCode(body.RoleCode) {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid invitation request"})
		return
	}
	lifetime, ok := invitationLifetime(body.ExpiresInHours)
	if !ok {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid invitation expiry"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	tx, err := api.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation unavailable"})
		return
	}
	defer tx.Rollback()
	principal, err := api.authenticateSessionTx(ctx, tx, r, "context")
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	issuerRole, orgType, err := activeContextRole(ctx, tx, principal)
	if err != nil || !mayInvite(orgType, issuerRole, body.RoleCode) {
		writeAuthJSON(w, http.StatusForbidden, map[string]string{"error": "invitation permission denied"})
		return
	}
	invite, token, err := api.insertInvitation(ctx, tx, principal, principal.OrganizationID.String, body.RoleCode, lifetime)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation unavailable"})
		return
	}
	if err := insertEnrollmentAudit(ctx, tx, principal.IdentityID, principal.OrganizationID.String, "enrollment.invitation.created", "success"); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation unavailable"})
		return
	}
	if err := tx.Commit(); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation unavailable"})
		return
	}
	writeInvitationResponse(w, invite, token)
}

func (api *googleIdentityAPI) redeemInvitation(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Token string `json:"invitation_token"`
	}
	if err := decodeStrictJSON(w, r, &body, 4096); err != nil || len(body.Token) < 40 || len(body.Token) > 128 {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid invitation"})
		return
	}
	raw, err := base64.RawURLEncoding.DecodeString(body.Token)
	if err != nil || len(raw) != 32 {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid invitation"})
		return
	}
	digest := keyedDigest(api.hmacKey, "account-invitation-token", body.Token)
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	tx, err := api.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation could not be accepted"})
		return
	}
	defer tx.Rollback()
	principal, err := api.authenticateSessionTx(ctx, tx, r, "identity")
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	var invite invitationRow
	var issuerIdentityID string
	err = tx.QueryRowContext(ctx,
		`SELECT v.invitation_id::text, v.organization_id::text, o.organization_type,
		        o.display_label, v.role_code, v.status, v.expires_at,
		        v.redeemed_membership_id::text, v.issuer_identity_id::text
		 FROM account_invitations v JOIN organizations o ON o.organization_id = v.organization_id
		 WHERE v.token_hmac = $1
		 FOR UPDATE OF v`, digest).Scan(
		&invite.ID, &invite.OrganizationID, &invite.OrganizationType, &invite.DisplayLabel,
		&invite.RoleCode, &invite.Status, &invite.ExpiresAt,
		&invite.RedeemedMembershipID, &issuerIdentityID)
	if err != nil {
		writeAuthJSON(w, http.StatusNotFound, map[string]string{"error": "invitation is unavailable"})
		return
	}
	if invite.Status == "redeemed" && invite.RedeemedMembershipID.Valid {
		var redeemedBy string
		err = tx.QueryRowContext(ctx,
			`SELECT redeemed_by_identity_id::text FROM account_invitations WHERE invitation_id = $1`,
			invite.ID).Scan(&redeemedBy)
		if err == nil && redeemedBy == principal.IdentityID {
			if err := tx.Commit(); err != nil {
				writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation could not be accepted"})
				return
			}
			writeAuthJSON(w, http.StatusOK, map[string]any{
				"status": invitationMembershipStatus(invite.RoleCode),
				"organization_name": invite.DisplayLabel,
				"role_code": invite.RoleCode,
				"membership_id": invite.RedeemedMembershipID.String,
			})
			return
		}
		writeAuthJSON(w, http.StatusConflict, map[string]string{"error": "invitation is unavailable"})
		return
	}
	if invite.Status != "pending" || !invite.ExpiresAt.After(time.Now()) {
		writeAuthJSON(w, http.StatusGone, map[string]string{"error": "invitation is unavailable"})
		return
	}
	var emailBound bool
	if err := tx.QueryRowContext(ctx,
		`SELECT recipient_email_hmac IS NOT NULL FROM account_invitations WHERE invitation_id = $1`,
		invite.ID).Scan(&emailBound); err != nil || emailBound {
		// The initial redemption API has no verified-email claim contract; fail closed for bound invitations.
		writeAuthJSON(w, http.StatusForbidden, map[string]string{"error": "invitation recipient verification is unavailable"})
		return
	}
	var existingMembershipID, existingStatus string
	err = tx.QueryRowContext(ctx,
		`SELECT membership_id::text, status FROM memberships
		 WHERE identity_id = $1 AND organization_id = $2 AND role_code = $3`,
		principal.IdentityID, invite.OrganizationID, invite.RoleCode).Scan(&existingMembershipID, &existingStatus)
	membershipID := ""
	if err == nil {
		if existingStatus != "active" {
			writeAuthJSON(w, http.StatusConflict, map[string]string{"error": "existing account access needs administrator review"})
			return
		}
		membershipID = existingMembershipID
	} else if errors.Is(err, sql.ErrNoRows) {
		membershipID, err = randomUUID()
		if err != nil {
			writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation could not be accepted"})
			return
		}
		status := "active"
		var approvedBy any = issuerIdentityID
		var approvedAt any = time.Now().UTC()
		if invite.RoleCode == "isp.customer" {
			// Customer workspace remains pending until identity/serviceability/payment checks complete.
			status = "invited"
			approvedBy = nil
			approvedAt = nil
		}
		_, err = tx.ExecContext(ctx,
			`INSERT INTO memberships
			 (membership_id, identity_id, organization_id, role_code, scope_json, status, approved_by, approved_at)
			 SELECT $1, $2, v.organization_id, v.role_code, v.scope_json, $3, $4, $5
			 FROM account_invitations v WHERE v.invitation_id = $6`,
			membershipID, principal.IdentityID, status, approvedBy, approvedAt, invite.ID)
		if err != nil {
			writeAuthJSON(w, http.StatusConflict, map[string]string{"error": "invitation could not be accepted"})
			return
		}
	} else {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation could not be accepted"})
		return
	}
	_, err = tx.ExecContext(ctx,
		`UPDATE account_invitations SET status = 'redeemed', redeemed_by_identity_id = $2,
		        redeemed_membership_id = $3, redeemed_at = now()
		 WHERE invitation_id = $1 AND status = 'pending' AND expires_at > now()`,
		invite.ID, principal.IdentityID, membershipID)
	if err != nil {
		writeAuthJSON(w, http.StatusGone, map[string]string{"error": "invitation is unavailable"})
		return
	}
	if err := insertEnrollmentAudit(ctx, tx, principal.IdentityID, invite.OrganizationID, "enrollment.invitation.redeemed", "success"); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation could not be accepted"})
		return
	}
	if err := tx.Commit(); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "invitation could not be accepted"})
		return
	}
	writeAuthJSON(w, http.StatusOK, map[string]any{
		"status": invitationMembershipStatus(invite.RoleCode),
		"organization_name": invite.DisplayLabel,
		"role_code": invite.RoleCode,
		"membership_id": membershipID,
	})
}

func (api *googleIdentityAPI) insertInvitation(ctx context.Context, tx *sql.Tx, issuer sessionPrincipal, organizationID, roleCode string, lifetime time.Duration) (invitationRow, string, error) {
	var invite invitationRow
	invite.ID, _ = randomUUID()
	if invite.ID == "" {
		return invite, "", errors.New("invitation id generation failed")
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return invite, "", err
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	invite.OrganizationID = organizationID
	invite.RoleCode = roleCode
	invite.Status = "pending"
	invite.ExpiresAt = time.Now().UTC().Add(lifetime)
	if err := tx.QueryRowContext(ctx,
		`SELECT organization_type, display_label FROM organizations WHERE organization_id = $1 AND status = 'active'`,
		organizationID).Scan(&invite.OrganizationType, &invite.DisplayLabel); err != nil {
		return invite, "", err
	}
	_, err := tx.ExecContext(ctx,
		`INSERT INTO account_invitations
		 (invitation_id, token_hmac, organization_id, issuer_identity_id, issuer_membership_id,
		  role_code, scope_json, status, expires_at)
		 VALUES ($1, $2, $3, $4, $5, $6, '{}'::jsonb, 'pending', $7)`,
		invite.ID, keyedDigest(api.hmacKey, "account-invitation-token", token),
		organizationID, issuer.IdentityID, issuer.MembershipID.String, roleCode, invite.ExpiresAt)
	return invite, token, err
}

func activeContextRole(ctx context.Context, tx *sql.Tx, principal sessionPrincipal) (string, string, error) {
	if !principal.OrganizationID.Valid || !principal.MembershipID.Valid {
		return "", "", errors.New("context session is incomplete")
	}
	var role, organizationType string
	err := tx.QueryRowContext(ctx,
		`SELECT m.role_code, o.organization_type
		 FROM memberships m JOIN organizations o ON o.organization_id = m.organization_id
		 JOIN identities i ON i.identity_id = m.identity_id
		 WHERE m.membership_id = $1 AND m.identity_id = $2
		   AND m.organization_id = $3 AND i.status = 'active'
		   AND m.status = 'active' AND m.approved_at IS NOT NULL
		   AND o.status = 'active' AND (m.expires_at IS NULL OR m.expires_at > now())`,
		principal.MembershipID.String, principal.IdentityID, principal.OrganizationID.String).Scan(&role, &organizationType)
	return role, organizationType, err
}

func mayInvite(orgType, issuerRole, invitedRole string) bool {
	if orgType == "omisha_workspace" {
		return issuerRole == "omisha.platform_admin" && invitedRole == "omisha.staff"
	}
	if orgType != "isp_tenant" {
		return false
	}
	switch issuerRole {
	case "isp.owner":
		switch invitedRole {
		case "isp.admin", "isp.technician", "isp.sales", "isp.support", "isp.finance", "isp.customer":
			return true
		}
	case "isp.admin":
		switch invitedRole {
		case "isp.technician", "isp.sales", "isp.support", "isp.finance", "isp.customer":
			return true
		}
	}
	return false
}

func validRoleCode(role string) bool {
	switch role {
	case "omisha.staff", "isp.owner", "isp.admin", "isp.technician", "isp.sales", "isp.support", "isp.finance", "isp.customer":
		return true
	default:
		return false
	}
}

func invitationMembershipStatus(role string) string {
	if role == "isp.customer" {
		return "pending_onboarding"
	}
	return "active"
}

func invitationLifetime(hours int) (time.Duration, bool) {
	if hours == 0 {
		return invitationDefaultLifetime, true
	}
	if hours < 1 || time.Duration(hours)*time.Hour > invitationMaximumLifetime {
		return 0, false
	}
	return time.Duration(hours) * time.Hour, true
}

func writeInvitationResponse(w http.ResponseWriter, invite invitationRow, token string) {
	writeAuthJSON(w, http.StatusCreated, map[string]any{
		"invitation_id": invite.ID,
		"organization_id": invite.OrganizationID,
		"organization_name": invite.DisplayLabel,
		"role_code": invite.RoleCode,
		"expires_at": invite.ExpiresAt.Format(time.RFC3339),
		"invitation_token": token,
	})
}

func insertEnrollmentAudit(ctx context.Context, tx *sql.Tx, actorIdentityID, organizationID, eventCode, outcome string) error {
	_, err := tx.ExecContext(ctx,
		`INSERT INTO security_audit_events
		 (actor_identity_id, organization_id, event_code, outcome, metadata)
		 VALUES ($1, $2, $3, $4, '{}'::jsonb)`,
		actorIdentityID, organizationID, eventCode, outcome)
	return err
}

var _ io.Reader
