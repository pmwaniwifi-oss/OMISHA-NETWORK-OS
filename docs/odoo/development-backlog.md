# NMS Prime + Odoo Community platform

## Development backlog

**Prepared:** 6 October 2026  
**Status:** Initial backlog; refine after discovery  
**Related documents:** [Technical architecture](technical-architecture.md) · [Project proposal](project-proposal.md)

Priority guide: **P0** = scope or safe-launch requirement; **P1** = initial production capability; **P2** = follow-up enhancement.

## Release 0 — Discovery and architecture gates

### E00 — Product, compliance, and interface discovery

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| D-001 | P0 | As product owner, I want NMS Prime product/version and integration surface documented. **Done when:** API/extension documentation, sandbox, auth, limits, data owner, supported operations, vendor contact, and gaps are approved by the NMS owner. |
| D-002 | P0 | As operations owner, I want data ownership and identifiers defined across Odoo, NMS, PM-WANI, and the app. **Done when:** customer, service, subscriber, ticket, payment, and network IDs have one owner, sync direction, conflict rule, and retention rule. |
| D-003 | P0 | As administrator, I want an Odoo Community release/module fit-gap. **Done when:** CRM, HR, accounting/GST, helpdesk, and API options list release, license, dependencies, and maintenance; critical workflows are demonstrated; unresolved Community/Enterprise choices are signed off. |
| D-004 | P0 | As PM-WANI owner, I want the operating role and current certification path confirmed. **Done when:** App Provider/PDOA/third-party role, Central Registry access, endpoints, token/auth method, key/certificate custody, test-plan version, test access, and external responsibilities are recorded. |
| D-005 | P0 | As finance/compliance owner, I want a verified reporting register. **Done when:** GSTINs, periods, approved outputs, GST/GSP decision, ISP/DoT obligations, evidence, preparer/reviewer, and due-date rules are documented. |
| D-006 | P0 | As sponsor, I want an agreed MVP and operating envelope. **Done when:** app audience/features, subscriber/user estimates, locations, support hours, hosting region, recovery targets, budget model, and release scope are approved. |

**Gate:** Do not commit production PM-WANI, GST automation, or Community helpdesk implementation until D-003 through D-005 are approved.

## Release 1 — Secure platform foundation

### E01 — Source, environments, identity, and operations

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| F-101 | P0 | As a developer, I want source in GitHub. **Done when:** repositories are established for Odoo addons, mobile/API, connectors, and deployment configuration; protected branches, code review, ownership, and secret policy are documented. |
| F-102 | P0 | As administrator, I want separate development, staging, and production. **Done when:** databases/credentials are isolated, production access is limited, deployment/rollback steps exist, and production data is not copied to dev without masking approval. |
| F-103 | P0 | As operations lead, I want backup and recovery. **Done when:** databases, required attachments, and configuration have approved backup/retention; access is restricted; a restore exercise is recorded against agreed targets. |
| F-104 | P0 | As security owner, I want controlled credentials and administration. **Done when:** TLS/private networking, MFA for staff administrators, least-privilege integration users, credential rotation, and emergency revocation owners are in place. |
| F-105 | P1 | As operations lead, I want core services visible in Zabbix. **Done when:** agreed Odoo, NMS, mobile API, integrations, databases, hosts, and network targets have availability/capacity alerts, owners, severity, and notification routes. |
| F-106 | P1 | As platform owner, I want production readiness reviewed. **Done when:** monitoring, restore, TLS, access review, release rollback, incident contacts, log retention, and capacity alerting are signed off. |

## Release 2 — Odoo business core

### E02 — CRM and customer/service records

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| O-201 | P1 | As a sales agent, I want leads and opportunities in Odoo. **Done when:** source, owner, stage, contact, next action, loss reason, conversion, roles, and duplicate handling are configured. |
| O-202 | P1 | As service administrator, I want customers linked to NMS service IDs. **Done when:** Odoo stores stable external IDs/status timestamps; users can search agreed IDs; an exception view shows missing/duplicate links. |
| O-203 | P1 | As manager, I want a pipeline report. **Done when:** stage, owner, source, age, and outcome are filterable with role access. |

### E03 — Helpdesk and HR

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| O-301 | P1 | As support agent, I want customer tickets. **Done when:** ticket has customer/service link, category, priority, owner, status, timestamps, history, and resolution reason; the Community module/version is approved. |
| O-302 | P1 | As support lead, I want SLA and escalation visibility. **Done when:** business calendar, response/resolution targets, breach indicator, and escalation owner are configured. |
| O-303 | P1 | As customer, I want to submit and follow a support case in the app. **Done when:** one request creates one Odoo ticket; status is returned safely; cross-customer access is denied. |
| O-304 | P1 | As HR administrator, I want employee records and selected workflows. **Done when:** employee, department, manager, active status, and approved leave/attendance/recruitment workflows are configured; sensitive fields are restricted; payroll remains out until approved. |
| O-305 | P2 | As employee, I want selected self-service tasks. **Done when:** HR approves the tasks, approval path, notifications, retention, and audit history. |

### E04 — Accounts, GST, and ISP compliance evidence

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| O-401 | P0 | As finance lead, I want accounting module fit confirmed. **Done when:** chart of accounts, taxes, invoices, credit/debit notes, receipts, reconciliation, multiple-GSTIN needs, audit trail, and report gaps are proven before build. |
| O-402 | P1 | As accountant, I want period GST data prepared for review. **Done when:** agreed export is reproducible by period, includes source references/exceptions, reconciles to sample ledger totals, and requires reviewer approval. |
| O-403 | P1 | As compliance owner, I want ISP/DoT obligations tracked. **Done when:** verified items include due period, preparer/reviewer, status, report version, evidence, and change history. |
| O-404 | P2 | As finance lead, I want an authorized GST/GSP filing route evaluated. **Done when:** provider/authorization is approved, credentials and obligations are confirmed, human review is required, and acknowledgements are retained. |
| O-405 | P1 | As auditor, I want report changes traceable. **Done when:** each run preserves period, timestamp, template/module version, cutoff, approver, and evidence; corrections do not overwrite prior filing records. |

## Release 3 — Network and PM-WANI integrations

### E05 — NMS Prime connector

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| I-501 | P0 | As integration owner, I want a read-only connectivity spike. **Done when:** staging auth retrieves one agreed service record and documents fields, latency, limits, and errors. |
| I-502 | P1 | As service administrator, I want approved changes sent to NMS. **Done when:** provisioning uses stable idempotency/correlation IDs, records NMS response, prevents duplicate records, and exposes retryable failures. |
| I-503 | P1 | As support staff, I want network state beside a ticket. **Done when:** only agreed NMS status/IDs are shown; NMS remains owner of changes; stale/error state is visible. |
| I-504 | P1 | As operations lead, I want an integration exception queue. **Done when:** failures show timestamp, correlation ID, category, retry action, and owner without exposing secrets. |
| I-505 | P2 | As manager, I want customer/service reconciliation. **Done when:** scheduled comparison identifies missing, duplicate, or mismatched links and assigns exceptions. |

### E06 — PM-WANI role and authentication

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| W-601 | P0 | As PM-WANI owner, I want a protocol-conformance spike. **Done when:** role, interface, certificates, endpoints, token format/lifecycle, timeout/retry, and test evidence are validated with authorized provider/Registry. |
| W-602 | P1 | As app user, I want the approved WANI discovery/auth journey. **Done when:** Flutter/API/adapter flow follows the approved test plan; success/failure states are clear; tokens are absent from client logs/analytics. |
| W-603 | P1 | As security owner, I want WANI secrets handled safely. **Done when:** credentials are outside source/mobile bundle, access is restricted, rotation/revocation is documented, expiry is monitored, and ordinary logs are redacted. |
| W-604 | P1 | As compliance owner, I want authentication records. **Done when:** correlation ID, timestamp, outcome, provider reference, and minimum allowed audit fields are retained under an approved policy, with secrets/tokens redacted. |
| W-605 | P1 | As release owner, I want certification evidence packaged. **Done when:** test cases, software/config version, evidence, certificate state, and external result are recorded; production is blocked pending required approval. |
| W-606 | P2 | As finance owner, I want usage/payment reconciliation. **Done when:** usage/payment references reconcile to provider and accounting records for a sample period; exceptions have owners and evidence. |

## Release 4 — Flutter app and customer API

### E07 — Mobile app and API

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| M-701 | P0 | As product owner, I want personas/MVP flows approved. **Done when:** user types, OS versions, language, identity provider, customer tasks, accessibility baseline, and privacy notice are signed off. |
| M-702 | P1 | As customer, I want a secure session. **Done when:** app only uses mobile API over TLS; expiry/revocation/sign-out work; identity errors are handled; no Odoo/NMS secrets are in the client. |
| M-703 | P1 | As customer, I want a service summary. **Done when:** API returns only permitted authenticated-customer fields; stale/unavailable NMS data is marked; app makes no direct Odoo/NMS database calls. |
| M-704 | P1 | As customer, I want support cases in the app. **Done when:** requests create one ticket, status is customer-scoped, and offline/retry handling prevents accidental duplicates. |
| M-705 | P1 | As customer, I want the approved PM-WANI flow. **Done when:** discovery, selection, token exchange, and errors pass provider/C-DOT scenarios; payment UI matches provider contract. |
| M-706 | P1 | As customer, I want service notifications. **Done when:** notifications respect consent and avoid sensitive lock-screen content by default. |
| M-707 | P0 | As security owner, I want app/API authorization reviewed. **Done when:** threat review covers account takeover, object access, abuse, token/secret leakage, PII logging, and findings are resolved or formally accepted. |
| M-708 | P1 | As app owner, I want controlled releases. **Done when:** signing keys are protected, test/production builds are distinct, privacy disclosures are approved, and rollback/update policy is documented. |

## Release 5 — Workflow automation and marketing

### E08 — n8n and content publishing

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| A-801 | P0 | As platform owner, I want restricted n8n hosting. **Done when:** workflow-specific credentials, limited editors, HTTPS, approved node policy, execution-data retention, backup, and security audit are in place. |
| A-802 | P1 | As support lead, I want approved notifications automated. **Done when:** ticket/activation events send once, duplicate events are idempotent, failures are visible and retryable. |
| A-803 | P1 | As content editor, I want a daily content calendar. **Done when:** channel, date, audience, source facts, approval state, owner, and publish status are recorded. |
| A-804 | P1 | As marketing editor, I want AI-assisted drafts. **Done when:** drafts use approved facts/brand guidance, show source inputs/provider, are marked drafts, and cannot publish before human approval. |
| A-805 | P1 | As marketing editor, I want approved content published. **Done when:** only approved posts are queued; outcome/error and remote ID are stored; rate limits are handled; unsupported channels use manual handoff. |
| A-806 | P0 | As business owner, I want ad spend protected. **Done when:** AI can draft/recommend, but budget/bid changes require separate named human approval and audit. |
| A-807 | P2 | As marketing lead, I want performance summaries. **Done when:** approved channel metrics use a defined period/attribution window and missing or estimated data is labeled. |

## Release 6 — UAT and handover

### E09 — Reconciliation, launch, and operations

| ID | Priority | User story and acceptance criteria |
|---|---|---|
| L-901 | P0 | As business owner, I want role-based UAT. **Done when:** finance, HR, sales, support, operations, and marketing owners approve workflows/reports; remaining defects have severity, owner, and decision. |
| L-902 | P0 | As administrator, I want initial data reconciled. **Done when:** approved imports reconcile to source totals; duplicates/rejections are recorded; owner signs off. |
| L-903 | P0 | As operations lead, I want cutover/rollback steps. **Done when:** owner, window, backup, release artifact, smoke checklist, rollback trigger, communications, and escalation contacts are approved. |
| L-904 | P0 | As support/operations, I want runbooks and training. **Done when:** guides cover access, integration retries, WANI expiry, restore, incident handling, report periods, and rollback; named staff complete training. |
| L-905 | P1 | As service owner, I want a 30-day stabilization review. **Done when:** availability, integration errors, ticket volume, report exceptions, feedback, security findings, and follow-up work are reviewed. |

## Suggested delivery order

1. D-001 through D-006: resolve scope and dependencies.
2. F-101 through F-106: secure environments and operating baseline.
3. O-201 through O-405: business workflows and report definitions.
4. I-501 through I-505 and W-601 through W-605: prove integrations; certification remains an external launch gate.
5. M-701 through M-708: build app against stable API contracts.
6. A-801 through A-807: enable approved automation and content workflows.
7. L-901 through L-905: reconcile, accept, launch, and stabilize.

## Definition of done

A story is complete when acceptance criteria are demonstrated in the agreed environment, access/audit/failure paths are considered, operator documentation is updated, and the named business owner accepts it. Integration stories record contract/version, correlation IDs, retry/idempotency, and support owner. Production work also requires monitoring, backup, rollback, and access ownership.

## Unresolved backlog inputs

- Odoo Community version, module license/maintenance policy, and fit.
- NMS Prime API and whether provisioning is supported read/write.
- PM-WANI role, current token/auth contract, provider/Registry/C-DOT prerequisites, and schedule.
- GST/GSP strategy, approved report layouts, and ISP/DoT duties for the company's authorization.
- App audience, authentication, languages, payment/notification services.
- Hosting region, traffic, availability and recovery targets.
- CMS/social channels, AI model/data policy, and daily approval owner.

