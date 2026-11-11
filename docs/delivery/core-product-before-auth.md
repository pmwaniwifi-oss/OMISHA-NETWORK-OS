# Core Product Delivery Order

**Decision:** NMS Prime is the network system of record and the first critical-path integration. Complete its deployed-version/API verification and a controlled network workflow, with Frappe/ERPNext owning business, payment and accounting records and Flutter calling both only through the OMISHA API. Complete these product layers before extending authentication. The current Google identity/invitation code is an early scaffold only; it is not an operational login release.

## What “complete first” means

Completion is a reviewable, integrated vertical slice—not merely adding menu screens or importing upstream source. Each phase has code, a reproducible environment, owner, and acceptance evidence. No legacy installer is run. External system writes stay disabled until their real contracts and test environments are identified.

## Ordered implementation

### 1. NMS Prime / network integration

**Discovery dependency**

The user's link resolves to nmsprime/nmsprime, whose README says the project moved to cablelabs/os-provisioning. The repository submodule is pinned to that official source at commit 117cf48e917681c6c47ba966132c2fbf1e606f4b. Its README describes the Community Edition OSS Provisioning layer for FTTH/DSL/WiFi using TR-069 and RADIUS; the official overview describes CPE/modem provisioning and BNG/BRAS/IP-pool/QoS management. The user's link therefore confirms the source identity. Still confirm which NMS Prime edition/release is deployed and that its host API spec matches the pinned source before integration.

**Scope after discovery**

- Build a narrow versioned adapter for NMS Prime's documented REST/JSON API under `/admin/api/v0` for only the needed customer/contract, product/QoS, CPE/ONT and status workflows. Pinned source uses HTTP Basic Auth (email as username), requires `use api`, and applies model-action abilities to generated REST routes. Create a dedicated API user with only required view rights for reads, then verify its actual abilities and custom action protections in the deployed release. Keep NMS private, use verified TLS and secret files, never expose its API to Flutter, and put a fixed allowlisted connector behind the OMISHA BFF. Confirm endpoint schemas and side effects from the matching deployed release before writes. Build provisioning, read-back, suspend/restore and deprovisioning only where that release supports them.
- Keep Frappe as business record owner and NMS/OLT/BNG/AAA as network-state authorities; correlate by stable service/device references, never names alone.
- Model zero-touch installation: technician records the device and optical/link result; supported ACS (TR-069/CWMP) or a separately verified USP Controller enrolls/configures compatible CPE; this pinned source documents TR-069/CWMP, not TR-369. The access/AAA path enables the subscriber session; only authoritative read-back/session evidence advances Active/Ready.
- Store no device-management or subscriber secrets in plaintext logs or Git. Use bounded retries, idempotency, reconciliation and a manual recovery queue.
- Keep all live provisioning writes behind explicit environment and operator gates until a controlled pilot proves rollback and recovery.

**Acceptance**

- Vendor-confirmed API contract and representative test device/site exist.
- First boot, duplicate/wrong device, interrupted provisioning, replacement/factory reset, stale profile, AAA reject, timeout/retry, suspend/restore and rollback are exercised in a controlled test environment.
- Successful provisioning read-back maps to exactly one service and tenant; failed/unknown devices never become Active.
- Replaying the same event cannot create duplicate network profiles or customer services.


### 2. Frappe / ERPNext business workflows

**Scope**

- Pin one compatible Frappe, ERPNext, CRM, Helpdesk, HR, and India Compliance release set and package the custom OMISHA ISP app into a reproducible image.
- Complete the client-site workflow for lead/customer, address, plan, service acquisition, technician installation, service order, Payment Request/Entry references, support links, and draft billing/reporting handoff; Frappe events coordinate the NMS workflow without becoming the network authority.
- Keep ERPNext as the single owner of customer/accounting documents; the custom ISP app owns workflow state, cross-system references, and the transactional outbox.
- Finish role/permission rules and server-side transitions; mobile clients must never set payment, identity, installation, NMS, or activation outcome fields.
- Add durable outbox dispatch, retry/backoff, dead-letter/reconciliation views, and idempotency. Outbox payloads remain references, not copies of ERPNext customer/payment data.
- Add controlled installation/upgrade/backup/restore procedures for a dedicated client Frappe site/database.

**Acceptance**

- A disposable client site can install/upgrade the pinned app reproducibly.
- Technician can close the installation with ONT/optical/link checks; workflow records one canonical service order and one outbox event.
- Duplicate/retried submissions do not create duplicate ERPNext or operations records.
- Payment remains ERPNext-owned; workflow cannot mark a payment confirmed from client input.
- Permissions prevent cross-client data access; failure/replay and restore procedures are documented and reviewable.

### 3. Flutter main app product flows

**Scope before auth release**

- Keep one Android app for customer, ISP staff/technician, sales and OMISHA staff; make role/workspace modules data-driven, not separate app forks.
- Build and wire the product flows against a versioned API contract: customer service overview/self-care onboarding progress, bill/payment status read-only views, helpdesk, service/install status, technician job queue/closeout, ISP admin customer/staff workflow, OMISHA tenant/support operations, and reporting/notifications as each backend is available.
- Use typed models, loading/empty/error/retry states, bounded pagination and minimal cached data. No sensitive data or credentials in logs or ordinary local storage.
- Use API contract fixtures or a non-production stub during UI work; never present fixtures as live service data. Do not disable authorization on server endpoints to make UI demos work.
- Keep the login screen and existing identity scaffold isolated behind a boundary; revisit production authentication after Frappe/NMS/API contracts are stable.

**Acceptance**

- Android host and all product screens compile in CI for the pinned Flutter/Android toolchain.
- Each screen is backed by a documented API schema and has explicit loading/empty/error behavior.
- Customer, technician, ISP-admin and OMISHA-admin flows show only their role-appropriate navigation/actions.
- UI has no hardcoded production credentials, endpoints or customer data; build configuration uses environment-specific public API origins.
- A controlled end-to-end journey can be shown from installation closeout to service Active/Ready and support/service visibility once backend integration is available.

### 4. Authentication and account security (later gate)

Resume only after phases 1–3 have stable API contracts and role/capability needs. Then validate Google identity, tenant membership, invitation/bootstrap, session lifecycle, account recovery, mobile security, and end-to-end authorization against the actual app/API. Existing source scaffolding remains unvalidated and does not make this phase complete.

## Dependencies and operator decisions

- Exact Frappe/ERPNext/CRM/Helpdesk/HR/India Compliance versions and the supported database choice.
- Exact NMS Prime product and version; clarify whether CableLabs OS provisioning is intended, a separate NMS Prime is used, or both.
- Network access topology and vendors: OLT/ONT, CPE models, BNG/BRAS/NAS, PPPoE/IPoE, AAA/RADIUS, TR-069 ACS or TR-369 USP controller; sample sanitized API contracts and a controlled test environment.
- Approved workflow rules for installation, charges/payment, activation, billing start, refunds, suspension/restoration and customer support.
- Final Flutter package ID, API domain, release signing owner, app privacy notice and supported Android device range.

## Current status (source review, not runtime validation)

| Layer | Repository evidence | Not complete |
|---|---|---|
| Frappe | Custom app source has ISP Acquisition Request, ISP Service Order, ISP Installation Job and reference-only ISP Integration Event DocTypes. Installation closeout validates assigned technician, device/check fields, and submits a reference-only outbox event. Gateway supports staff-only read projections for acquisition/service order. | App is not installed or packaged into a validated image; no customer self-care or technician closeout API, outbox dispatcher, payment integration, live NMS writer, full role review or production workflows. New source has not been build/runtime validated. |
| NMS | `nmsprime/nmsprime` redirects to the official `cablelabs/os-provisioning` repository; the project pins commit `117cf48e917681c6c47ba966132c2fbf1e606f4b`. Official docs describe FTTH/DSL/WiFi provisioning via TR-069/RADIUS and a REST/JSON API at `/admin/api/v0`. Go integration source has bounded Frappe projections and minimal NMS contract-number/CPE-MAC lookups; a tenant-scoped staff BFF route exposes only a contract ID reference. | Deployed NMS Prime edition/release and its exact OpenAPI schema are not confirmed. Pinned source uses Basic Auth, a `use api` ability, and model-action checks on generated routes. Deployed user abilities and custom action protections still require operator verification; the adapter must remain allowlisted and read-only until then. No active provisioning integration or controlled end-to-end test exists. |
| Flutter main app | Single Android Flutter source tree, workspace/invitation admin, and ISP staff lookup screen now call typed BFF reads for Frappe acquisition/service-order projections and NMS contract references. | Customer self-care, technician installation list and exact NMS modem-reference match are in source; customer self-care, closeout, provisioning writes and other product modules are incomplete; the current head has not been Android-built; auth itself remains unvalidated. |
| Environment | Compose and preflight configuration are source-only. | No service was started and no legacy installer was executed; local component availability must be inspected in the target laptop VM. |

## Guardrails

- This sequence does not remove existing code or claim unfinished code is complete.
- Do not install packages, start internet-facing services, execute legacy installers, or write production network/customer data as part of this development phase.
- Keep the repository public as previously selected; all secrets, private runtime configuration, signing keys, device credentials and customer data stay out of GitHub.
- Do not claim “fast/no-lag,” compliance certification, or provisioning success without measured tests and operator evidence.
