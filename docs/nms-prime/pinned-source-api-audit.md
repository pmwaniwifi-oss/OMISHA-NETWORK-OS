# NMS Prime pinned-source API audit

**Review date:** 11 November 2026  
**Reviewed source:** `cablelabs/os-provisioning` commit `117cf48e917681c6c47ba966132c2fbf1e606f4b`, matching the `upstream/nms` submodule gitlink.

This document records source-level facts. It does not verify that the ISP's deployed NMS Prime product, edition, custom modules, or API schema matches this source.

## NMS Prime is the network authority

NMS Prime owns network subscriber/contract and CPE/ONT provisioning state, including the network-side profile that ultimately drives access services. ERPNext/Frappe remains authoritative for business customer, payment, accounting, and statutory records. OMISHA's gateway joins these systems with stable tenant-scoped service/device references; it must not become a second NMS or store another copy of credentials.

For a fiber service, the intended network path is: installed ONT is identified by its supported device identifiers; the NMS ACS/provisioning system applies a compatible profile; the access/AAA system authorizes the resulting subscriber session; verified NMS/AAA read-back then allows OMISHA to show the service as active. A MAC-to-record match alone is only a reconciliation result.

## Pinned source API behavior

| Source path | Finding | OMISHA consequence |
|---|---|---|
| `app/extensions/core/BaseRoute.php` | Model resources are mounted under the admin prefix with `/api/v{ver}` routes. v0 includes generic GET index/get, POST create, PUT/PATCH update, and DELETE. The API index applies each query parameter as a direct Eloquent `where` condition. | The adapter can use exact filters such as `Contract?number=...` and `Modem?mac=...`; parameter names and returned model shape still need to match the deployed build. |
| `app/Http/Middleware/AuthenticateNmsPrimeApi.php` | API v0 uses HTTP Basic authentication and checks the `use api` ability. Route middleware adds model abilities such as view, create, update, or delete. | Keep credentials server-side and isolate the adapter. A restricted API user may still have broad rights; verify deployed abilities before enabling it. |
| `app/Http/Controllers/BaseController.php` (`api_index`, `api_get`, `api_store`, `api_update`) | v0 index returns `success` plus `models`; get returns a full Eloquent model object; generic create/update call model validation and normal Eloquent persistence hooks. The shown v0 methods do not accept an idempotency key and do not provide field projection for generic `api_get`. | Do not expose raw NMS objects to Flutter or pass sensitive full model responses through. Keep exact fixed query paths and project only required fields in the gateway. Do not enable automatic retries for mutations without an idempotency design. |
| `modules/ProvBase/Http/routes.php` | Custom action routes include GET `/Modem/{id}/restart`, `factoryReset`, `blockDhcp`, `unblockDhcp`, `unsetDns`, `setWifi`, `setLanMode`, and `createSyncPreset`; several are state-changing despite using GET. | Never route user-supplied or arbitrary NMS paths/methods. These actions must not be treated as ordinary reads or called by a generic proxy. |
| `modules/ProvBase/Observers/ModemObserver.php` | Creating a modem sets a generated hostname, updates RADIUS, and normally saves again, invoking update behavior that writes DHCP/configuration and service changes; some configured modules enqueue controller intents. | A generic POST to create a modem is a live provisioning operation with side effects. It needs a controlled pilot, explicit idempotency, per-device allowlists, read-back, rollback/reconciliation, and operator approval before it is enabled. |
| `modules/ProvBase/Observers/ContractObserver.php` | Contract create/update can geocode and update related records; changes to access/QoS fields can push changes to attached modems, while billing/module-dependent behavior also exists. | Do not model a generic contract POST as a harmless CRM record write. Confirm enabled NMS modules and site-specific effects first. |
| `modules/ProvBase/Entities/Modem.php` | The pinned source calls GenieACS at `http://localhost:7557`, looks up a device using its serial number, and can create a sync preset plus a connection-request task. | ACS is an internal NMS dependency in this code path. OMISHA should call a narrow NMS adapter, not connect directly to GenieACS from Flutter or expose ACS publicly. Device model, serial identity, configfile, QoS and credentials are site-specific prerequisites. |

The upstream README describes Community Edition provisioning for FTTH/DSL/WiFi using TR-069 and RADIUS. TR-369/USP support is not inferred from this pinned source. The deployment must confirm supported ONT models and ACS path. The term “TR2” has not been treated as a protocol specification.

## Implemented OMISHA NMS boundary

The Go integration client has a fixed NMS origin per ISP organization, verified HTTPS, bounded response size, disabled redirects, and exact allowlisted read paths. It has exact contract-number and modem-MAC lookups; the technician's NMS reference endpoint first verifies the assigned open Frappe job, then looks up its recorded ONT MAC inside that same ISP's NMS. It returns only the matching NMS modem ID. Ambiguous matches fail closed.

This is a source-level linkage only. It does not configure the modem, contact ACS, authorize a PPPoE/IPoE session, test RADIUS/BNG state, or activate service. The install queue and NMS match have not been runtime-validated against an actual NMS deployment.

## Required gates before network writes

1. Operator identifies the deployed NMS Prime edition, version/commit, enabled modules, private base URL, TLS certificate, and supported API/OpenAPI spec. Compare its routes and response fields with the pin.
2. Operator maps ONT vendors/models and accepted serial/MAC rules, configfile, QoS/profile, service type, and installation-to-NMS object references for a controlled test tenant.
3. Confirm how the site represents service activation across NMS, ACS/GenieACS, RADIUS/AAA, and BNG/NAS; define the authoritative read-back required for Active/Ready.
4. Design a durable deduplication key and state machine for NMS writes. On timeout, reconcile by stable external service/device key before retrying. A timeout must never cause a second modem/contract or blind repeated restart/reset.
5. Restrict private network reachability, secrets, operator scopes, rate limits, audit events, rollback, and a manual dead-letter/reconciliation path. Run only against a disposable or controlled pilot target after the matching deployment contract is reviewed.

No legacy installer was run and no NMS runtime request or mutation was made during this audit.
