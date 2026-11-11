# Gateway Frappe / NMS Prime Read API

**Status:** Source-only staff lookup slice. No live ERP/NMS connection is enabled by default, and no NMS write/provisioning operation is exposed here.

## Private tenant integration registry

At gateway start, set OMISHA_INTEGRATION_REGISTRY_FILE to an operator-managed secret file outside Git. The JSON contains one entry per ISP organization UUID:

    {
      "tenants": [
        {
          "organization_id": "00000000-0000-4000-8000-000000000001",
          "frappe_origin": "https://frappe.internal.example",
          "frappe_api_key": "runtime-secret",
          "frappe_api_secret": "runtime-secret",
          "frappe_technicians": {
            "11111111-1111-4111-8111-111111111111": "technician@example.invalid"
          },
          "nms_origin": "https://nms.internal.example",
          "nms_username": "integration-user@example.invalid",
          "nms_password": "runtime-secret"
        }
      ]
    }

This is a schema illustration only; the example UUID and credentials are not real. Restrict the file and parent directory to the gateway operator, mount it as a runtime secret, rotate the credentials, and never add it to the public repository or log its contents. Each organization UUID maps to one Frappe site and one NMS host. The request cannot supply or override that tenant mapping. Missing registry configuration makes these routes return unavailable.

The `frappe_technicians` map is optional and operator-maintained. Keys are OMISHA identity UUIDs and values are the corresponding Frappe User IDs; never accept this mapping from a mobile request. The Frappe user must have the ISP Technician role and be the `assigned_technician` on each job. The map contains account identifiers, so keep it in the private runtime secret file.

The NMS Prime API docs describe Basic Auth and the default API user as full create/modify/delete access; fine-grained API permissions are described as planned. Although these gateway methods issue GET requests only, the NMS credential is high impact. Keep the NMS origin on a private network with verified TLS; do not expose its admin API to Flutter or the public internet. If a service user cannot be restricted in the deployed release, isolate the connector at the network layer and review the risk before enabling the registry.

## Flutter-facing routes

All routes require a server-issued context-scoped bearer token. The gateway revalidates the active ISP membership and role on every call, then resolves the Frappe/NMS connection using the membership's organization UUID.

| Route | Allowed roles | Returned data |
|---|---|---|
| GET /v1/me/isp/acquisitions/{id} | isp.owner, isp.admin, isp.support | Minimal onboarding state, plan reference, identity state and ERPNext Payment Request / Service Order references. No lead contact/address or payment details. |
| GET /v1/me/isp/service-orders/{id} | isp.owner, isp.admin, isp.support | Name, plan reference, service state and NMS external service reference. No customer profile or raw NMS object. |
| GET /v1/me/isp/nms/contracts/{number} | isp.owner, isp.admin | Exact NMS contract number lookup returning only the NMS object ID. Multiple matches return conflict for manual reconciliation. |
| GET /v1/me/isp/technician/installation-jobs | isp.technician | At most 50 open jobs assigned to the authenticated technician's operator-mapped Frappe user; returns device references and installation checks only. |

The Flutter app has typed clients for these reads, a staff lookup screen, and a technician's assigned open-job list. The technician list is read-only: closeout submission is not yet available from Flutter. Backend business authorization is independent of UI visibility. Customers do not have these broad lookup privileges; customer-to-ERP customer ownership mapping remains unimplemented. No acquisition creation, payment, contract creation, modem creation, install closeout API, or provisioning write is available from Flutter.

## Data ownership and next slice

ERPNext/Frappe remains authoritative for its acquisition/service-order and installation-job workflow. NMS Prime remains authoritative for NMS contract/CPE/network objects. The gateway returns narrow projections and references. The closeout write path, stable customer/service-to-NMS mapping, and any idempotent provisioning writer must be added only after site-specific API schemas, authorization, idempotency and write effects are reviewed. The existing integration client refuses ambiguous NMS contract matches.

## Validation

This technician queue slice has not been built or integration-tested. The runtime registry and technician mapping have not been configured, migrations have not been applied, and no service was started or network request sent.
