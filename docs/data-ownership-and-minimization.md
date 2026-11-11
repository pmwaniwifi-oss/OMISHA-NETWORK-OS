# Data ownership and duplication control

## Rule

हर business fact का एक authoritative owner रखें। बाकी systems stable source ID, link या समय-सीमित cache रखें—customer की पूरी profile और transaction copy करके दूसरा master न बनाएं। Client separation अलग database/network boundary है; इसका अर्थ हर system में पूरी customer table की duplicate copy नहीं है।

## Data ownership map

| Data | Authoritative system | Other systems keep |
|---|---|---|
| Customer legal identity, contact and GST registration | Per-client ERPNext site | ERP customer ID; only minimal transient operational fields where NMS provisioning needs them |
| Invoice, payment, tax and general ledger | ERPNext | Invoice/payment reference and reconciled totals; no GL copy into NMS |
| ISP service order and financial plan | ERPNext | Outbox: service-order ID, schema version, stable event/idempotency key |
| Active service, credentials reference, network topology | NMS Prime | NMS contract/service/device IDs in ERPNext; ERP must not reconstruct topology |
| Health, alarms and performance time series | Zabbix | Alert ID, severity, timestamp, target service/device reference |
| PM-WANI authentication and session | System/provider authorised for the operator's role | External session/token reference and reconciled totals; never mirror secrets or full provider session store |
| Raw RADIUS/IPDR/CGNAT evidence | Ingest/archive pipeline under applicable retention | Archive URI, date range, byte count and cryptographic digest |
| Staff identity and HR record | Frappe HR | Minimum operator ID and role needed for support/approval audit |
| Generated government report | Reporting registry | Approved artifact, template version, values, source IDs and source digest; no duplicate source rows/attachments |
| Attachments | One designated private object store or owning Frappe site | URI, owner, checksum and access policy |
| API/cache response | Original system | Valkey derived value with short TTL only |

NMS Prime contains CRM/BSS features too. In OMISHA, ERPNext owns customer/accounting facts. Map supported NMS records to ERP customer IDs and limit updates to any minimal required contact projection. Confirm whether the selected NMS edition permits disabling unused CRM/BSS features. Until confirmed, that small operational projection is controlled duplication and must have a named owner and conflict policy.

## Cross-system contracts

Consumers query the owner through an authenticated service API only when current source fields are needed; they do not read another application's database directly. A future outbox message may use this minimal envelope:

```json
{
  "event_id": "ISP Integration Event document name",
  "event_type": "service_order.submitted",
  "schema": "isp.service-order.submitted.v1",
  "occurred_at": "UTC timestamp",
  "source": {"system": "erpnext", "doctype": "ISP Service Order", "id": "order-id"},
  "idempotency_key": "service-order:order-id:submitted",
  "data": {"service_order_id": "order-id"}
}
```

The authenticated client/site connection supplies tenant scope outside the business payload. A request body must never choose or override its tenant. Do not include customer name/contact/GST profile, plan description, invoice history, passwords, tokens, attachments, or raw NMS responses. If a provisioning operation requires a field, resolve it from the owning order and send only that approved field.

Event ID and idempotency key stay stable across retries. A receiver must enforce uniqueness on (authenticated tenant, source system, idempotency key) and return the original result for replay. This provides effectively-once processing through idempotency and reconciliation, not exactly-once network delivery.

## Projections, cache, and attachments

- ERPNext's NMS reference and service status are projections, never a second topology or credential store.
- Every projection needs a named owner, field allowlist, refresh/update trigger, and conflict policy.
- Valkey entries need source, key scope, TTL, and invalidation rule. Cache misses resolve from the owner.
- Attachments have one private binary owner; others retain URI/reference, checksum, and access metadata. Deduplicate only within the tenant and after authorization checks; do not expose cross-tenant equality or content.
- Backups/DR replicas are encrypted recovery copies with retention and restore controls, not writable operational masters.

## Reports and logs

The report engine streams bounded records, accumulates requested totals, and retains source IDs/dates and digests. Keep the final approved artifact when retention requires it, plus template/signature references; do not persist all source rows or duplicate source attachments in a second database.

Raw ISP evidence/log retention must follow the applicable operator and regulatory policy. Compress losslessly and keep one authoritative archive with indexed references. Reporting, search, and dashboards keep date/tenant references, bounded aggregates, and hashes rather than another raw log store.

## Retry and reconciliation gate

A future outbox consumer must claim work with an expiring lease, use exponential backoff with jitter, cap attempts, redact and bound error summaries, and expose a reviewable dead-letter state. Reconciliation compares event IDs and external references and retries only idempotently. Do not enable NMS writes until the supported write API, auth scope, error semantics, and idempotency behavior are confirmed against the pinned NMS release.

## Acceptance checks for every integration

1. Name owner, consumer, field allowlist, stable ID, and deletion/retention behavior.
2. Prove retries cannot create a second customer, service, invoice, PM-WANI session, or report.
3. Verify payloads contain no unneeded personal data, secrets, attachments, or full source rows.
4. Measure bytes by source, projection, cache, index, report, and backup; define per-client budgets.
5. Prove tenant scope comes from authenticated deployment configuration and cross-client references are denied.
6. Prove cache expiry and owner recovery after cache loss.
7. Version schemas and document migration; do not silently duplicate a field to avoid resolving ownership.

## Resource costs and status

Per-client MariaDB/PostgreSQL containers isolate credentials, upgrades, failure, and backups but add RAM, disk, filesystem, and backup overhead. Container boundaries do not add host capacity. Avoid cross-system polling loops, batch outbox events, paginate queries, cache small read-mostly projections, and measure disk/RAM per tenant before scaling. Backups are intentional copies governed by separate retention and recovery policy.

Implemented: transactional Frappe outbox with service-order reference; report runs retain source references/digests rather than full rows; Go integration adapters are read-only. The Frappe app is source-only and has not been installed on a site. No outbox worker or live NMS write path exists. Frappe, NMS, Zabbix and n8n database separation is described; only ERP and opt-in NMS PostgreSQL Compose configurations exist so far. Customer identity mapping, NMS projection policy, aggregate reporting, attachment deduplication and retention jobs still require implementation.


## Pinned NMS API audit

At pinned NMS source `cablelabs/os-provisioning@117cf48e917681c6c47ba966132c2fbf1e606f4b`, `modules/ProvBase/Http/routes.php` registers Contract as a BaseRoute resource. The pinned `app/extensions/core/BaseRoute.php` creates `POST /admin/api/v{ver}/Contract` and `PATCH/PUT /admin/api/v{ver}/Contract/{id}` routes behind the API middleware and model abilities (`can:create` / `can:update`). It also registers DELETE. Therefore this is a real mutable API surface, and the existing read-only adapter is a deliberate boundary.

Route existence alone is not a safe provisioning contract. Before enabling a worker, confirm the exact required fields and controller/base-service side effects for the deployed edition, API principal permissions, duplicate detection, whether contract creation provisions network equipment, and how update/delete affect billing and device state. The inspected route definitions do not expose an idempotency-key contract. Until these checks and a safe replay/reconciliation design are complete, OMISHA must not call the NMS write routes automatically.