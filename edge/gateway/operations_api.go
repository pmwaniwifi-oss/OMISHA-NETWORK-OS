package main

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"regexp"
	"time"

	"omisha.network/edge-gateway/integrations"
)

var operationDocumentName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9 ._-]{0,139}$`)
var operationNMSNumber = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`)

type operationsAPI struct {
	identity    *googleIdentityAPI
	integrations *tenantIntegrationRegistry
}

func (api *operationsAPI) authorizeISPStaff(ctx context.Context, r *http.Request, roles ...string) (sessionPrincipal, string, error) {
	var empty sessionPrincipal
	if api == nil || api.identity == nil || api.identity.db == nil || api.identity.configErr != nil {
		return empty, "", errors.New("operations unavailable")
	}
	principal, err := api.identity.authenticateSession(ctx, r, "context")
	if err != nil || !principal.OrganizationID.Valid || !principal.MembershipID.Valid {
		return empty, "", errors.New("authentication required")
	}
	var role string
	err = api.identity.db.QueryRowContext(ctx,
		`SELECT m.role_code
		 FROM memberships m
		 JOIN organizations o ON o.organization_id = m.organization_id
		 JOIN identities i ON i.identity_id = m.identity_id
		 WHERE m.membership_id = $1 AND m.identity_id = $2 AND m.organization_id = $3
		   AND m.status = 'active' AND m.approved_at IS NOT NULL
		   AND (m.expires_at IS NULL OR m.expires_at > now())
		   AND o.organization_type = 'isp_tenant' AND o.status = 'active'
		   AND i.status = 'active'`,
		principal.MembershipID.String, principal.IdentityID, principal.OrganizationID.String,
	).Scan(&role)
	if err != nil {
		return empty, "", errors.New("account access unavailable")
	}
	for _, allowed := range roles {
		if role == allowed {
			return principal, role, nil
		}
	}
	return empty, "", errors.New("account access unavailable")
}

func (api *operationsAPI) getAcquisition(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	principal, _, err := api.authorizeISPStaff(ctx, r, "isp.owner", "isp.admin", "isp.support")
	if err != nil {
		writeOperationsError(w, err)
		return
	}
	name := r.PathValue("acquisitionID")
	if !operationDocumentName.MatchString(name) {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid acquisition reference"})
		return
	}
	target, err := api.integrations.forOrganization(principal.OrganizationID.String)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "operations integration unavailable"})
		return
	}
	projection, err := target.frappe.Acquisition(ctx, principal.OrganizationID.String, name)
	if err != nil {
		writeIntegrationError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeAuthJSON(w, http.StatusOK, map[string]any{"acquisition": projection})
}

func (api *operationsAPI) getServiceOrder(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	principal, _, err := api.authorizeISPStaff(ctx, r, "isp.owner", "isp.admin", "isp.support")
	if err != nil {
		writeOperationsError(w, err)
		return
	}
	name := r.PathValue("serviceOrderID")
	if !operationDocumentName.MatchString(name) {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid service order reference"})
		return
	}
	target, err := api.integrations.forOrganization(principal.OrganizationID.String)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "operations integration unavailable"})
		return
	}
	projection, err := target.frappe.ServiceOrder(ctx, principal.OrganizationID.String, name)
	if err != nil {
		writeIntegrationError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeAuthJSON(w, http.StatusOK, map[string]any{"service_order": projection})
}

func (api *operationsAPI) getNMSContractReference(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	principal, _, err := api.authorizeISPStaff(ctx, r, "isp.owner", "isp.admin")
	if err != nil {
		writeOperationsError(w, err)
		return
	}
	number := r.PathValue("number")
	if !operationNMSNumber.MatchString(number) {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid contract reference"})
		return
	}
	target, err := api.integrations.forOrganization(principal.OrganizationID.String)
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "operations integration unavailable"})
		return
	}
	id, err := target.nms.ContractIDByNumber(ctx, principal.OrganizationID.String, number)
	if err != nil {
		writeIntegrationError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeAuthJSON(w, http.StatusOK, map[string]any{"contract_reference": map[string]any{
		"number": number,
		"nms_id": id,
	}})
}

func writeOperationsError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		writeAuthJSON(w, http.StatusGatewayTimeout, map[string]string{"error": "operations request timed out"})
	case err.Error() == "authentication required":
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
	default:
		writeAuthJSON(w, http.StatusForbidden, map[string]string{"error": "account access unavailable"})
	}
}

func writeIntegrationError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, integrations.ErrNotFound):
		writeAuthJSON(w, http.StatusNotFound, map[string]string{"error": "operations record not found"})
	case errors.Is(err, integrations.ErrAmbiguous):
		writeAuthJSON(w, http.StatusConflict, map[string]string{"error": "operations record needs reconciliation"})
	case errors.Is(err, integrations.ErrTenant):
		writeAuthJSON(w, http.StatusForbidden, map[string]string{"error": "account access unavailable"})
	case errors.Is(err, integrations.ErrUpstream):
		writeAuthJSON(w, http.StatusBadGateway, map[string]string{"error": "operations system unavailable"})
	case errors.Is(err, sql.ErrNoRows):
		writeAuthJSON(w, http.StatusNotFound, map[string]string{"error": "operations record not found"})
	default:
		writeAuthJSON(w, http.StatusBadGateway, map[string]string{"error": "operations system unavailable"})
	}
}
