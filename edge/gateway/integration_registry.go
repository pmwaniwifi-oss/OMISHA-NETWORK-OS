package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"regexp"
	"strings"

	"omisha.network/edge-gateway/integrations"
)

type tenantIntegrationRegistry struct {
	tenants map[string]tenantIntegrationClients
	err     error
}

type tenantIntegrationClients struct {
	frappe *integrations.Client
	nms    *integrations.Client
	frappeTechnicians map[string]string
}

type tenantIntegrationConfig struct {
	OrganizationID string `json:"organization_id"`
	FrappeOrigin   string `json:"frappe_origin"`
	FrappeAPIKey   string `json:"frappe_api_key"`
	FrappeAPISecret string `json:"frappe_api_secret"`
	NMSOrigin      string `json:"nms_origin"`
	NMSUsername    string `json:"nms_username"`
	NMSPassword    string `json:"nms_password"`
	FrappeTechnicians map[string]string `json:"frappe_technicians"`
}

var frappeUserIDPattern = regexp.MustCompile(`^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]{1,120}$`)

type integrationRegistryFile struct {
	Tenants []tenantIntegrationConfig `json:"tenants"`
}

// loadTenantIntegrationRegistry reads operator-managed runtime secret material.
// The file path and contents must never be committed to the public repository.
func loadTenantIntegrationRegistry() *tenantIntegrationRegistry {
	registry := &tenantIntegrationRegistry{tenants: make(map[string]tenantIntegrationClients)}
	path := strings.TrimSpace(os.Getenv("OMISHA_INTEGRATION_REGISTRY_FILE"))
	if path == "" {
		registry.err = errors.New("integration registry is not configured")
		return registry
	}
	info, err := os.Stat(path)
	if err != nil || info.Size() <= 0 || info.Size() > 1<<20 {
		registry.err = errors.New("integration registry is unavailable")
		return registry
	}
	data, err := os.ReadFile(path)
	if err != nil {
		registry.err = errors.New("integration registry is unavailable")
		return registry
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var config integrationRegistryFile
	if err := decoder.Decode(&config); err != nil {
		registry.err = errors.New("integration registry is invalid")
		return registry
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF || len(config.Tenants) == 0 || len(config.Tenants) > 500 {
		registry.err = errors.New("integration registry is invalid")
		return registry
	}
	for _, tenant := range config.Tenants {
		if !challengeIDPattern.MatchString(tenant.OrganizationID) {
			registry.err = errors.New("integration registry is invalid")
			return registry
		}
		frappeClient, err := integrations.NewFrappe(
			tenant.OrganizationID, tenant.FrappeOrigin, tenant.FrappeAPIKey, tenant.FrappeAPISecret,
		)
		if err != nil {
			registry.err = errors.New("integration registry is invalid")
			return registry
		}
		if len(tenant.FrappeTechnicians) > 10000 {
			registry.err = errors.New("integration registry is invalid")
			return registry
		}
		for identityID, userID := range tenant.FrappeTechnicians {
			if !challengeIDPattern.MatchString(identityID) || !frappeUserIDPattern.MatchString(userID) {
				registry.err = errors.New("integration registry is invalid")
				return registry
			}
		}
		nmsClient, err := integrations.NewNMSPrime(
			tenant.OrganizationID, tenant.NMSOrigin, tenant.NMSUsername, tenant.NMSPassword,
		)
		if err != nil {
			registry.err = errors.New("integration registry is invalid")
			return registry
		}
		if _, exists := registry.tenants[tenant.OrganizationID]; exists {
			registry.err = errors.New("integration registry is invalid")
			return registry
		}
		registry.tenants[tenant.OrganizationID] = tenantIntegrationClients{
			frappe: frappeClient,
			nms:    nmsClient,
			frappeTechnicians: tenant.FrappeTechnicians,
		}
	}
	return registry
}

func (registry *tenantIntegrationRegistry) forOrganization(organizationID string) (tenantIntegrationClients, error) {
	if registry == nil || registry.err != nil {
		return tenantIntegrationClients{}, errors.New("integration registry unavailable")
	}
	target, exists := registry.tenants[organizationID]
	if !exists {
		return tenantIntegrationClients{}, errors.New("tenant integration unavailable")
	}
	return target, nil
}
