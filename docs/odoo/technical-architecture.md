# NMS Prime + Odoo Community platform

## Technical architecture

**Status:** Initial solution outline  
**Prepared:** 6 October 2026  
**Purpose:** Starting architecture for an Indian ISP platform integrating business operations, network operations, PM-WANI, customer mobile services, monitoring, and digital marketing.

## 1. Summary

Use Odoo Community as the business system of record, NMS Prime as the network and subscriber operations system, and separate services for mobile APIs, PM-WANI protocol handling, workflow automation, and infrastructure monitoring. Keep each product's database private and exchange only authenticated, versioned business requests or events.

The Flutter application is a client. Its dedicated backend/API server handles authentication, app-specific rules, and integrations. The mobile app must not connect directly to Odoo, NMS Prime, a database, or Zabbix.

Keep latency-sensitive PM-WANI authentication and network provisioning out of n8n. Dedicated adapters handle those paths. Use n8n for asynchronous office workflows, notifications, approvals, and approved content publication.

## 2. Assumptions and decisions to validate

1. NMS Prime is an existing or separately maintained ISP network/subscriber platform. Its product version, data model, interfaces, and support policy are unknown in this workspace.
2. The company intends to run Odoo Community self-hosted. Exact version and module set are not selected.
3. “PM-WANI token” means the WANI app-token/authentication flow, including the waniapptoken exchange where applicable. A WANI API key/certificate is a separate credential.
4. The Flutter app is initially customer-facing; staff mobile use is not specified.
5. GST and ISP statutory outputs will be prepared and reviewed by authorized finance/compliance staff. This design does not interpret obligations or assume automatic filing.
6. No NMS Prime, PM-WANI, payment, CMS, or social API credentials/specifications are available yet.

## 3. Logical system view

```text
Customers -> Flutter app -> Dedicated Mobile API -> Odoo Community
                                  |                  |
                                  |                  +-- Odoo connector module
                                  +-- PM-WANI adapter ------> Central Registry / PDOA
                                  +-- NMS adapter ----------> NMS Prime

Staff -> Odoo Community -> reviewed finance/compliance reports
Operations -> NMS Prime and Zabbix
n8n <-> approved Odoo / NMS / CMS / social interfaces
Zabbix -> monitors applications, hosts, integration services, and network collection
GitHub -> reviewed build and deployment pipeline -> application environments
```

This is a logical view, not a final hosting topology. Capacity and high availability depend on subscriber volume, transaction rates, locations, and agreed recovery targets.

## 4. Service boundaries and data ownership

| Component | Owns or does | Does not own |
|---|---|---|
| Odoo Community | Leads, customer/contact master, HR records, helpdesk records, finance/invoice data where selected modules support the workflow, reviewed reporting data | Live subscriber authentication, network state, device telemetry |
| NMS Prime | Subscriber/service provisioning and status, plans, network inventory and operational data according to its current capabilities | General ledger or statutory filing evidence |
| Odoo Community helpdesk module | Support tickets, ownership, communication history, SLA and closure | Network monitoring and subscriber access control |
| Mobile API service | Customer app sessions, app-specific endpoints, request validation, notifications and adapter orchestration | Odoo/NMS records as master data |
| PM-WANI adapter | Role-specific protocol, token flow, endpoint/certificate configuration, authentication and certification evidence | Replacing PDOA or Central Registry |
| n8n | Asynchronous workflow orchestration, notifications, approvals, scheduled content and non-critical synchronization | Synchronous WANI authentication, primary financial posting, high-volume telemetry |
| Zabbix | Availability/performance monitoring, thresholds, alerts and distributed collection | Customer master or ticket system of record |
| GitHub | Versioned source, review, build and release history | Production secrets or live customer data |

Ownership rules:

- Odoo owns customer identity/contact data after deduplication. NMS Prime owns operational service identifiers, provisioning state, and network-side history.
- Odoo owns invoices, receipts, ledger entries, and approved accounting exports. Payment providers remain authoritative for transaction status until reconciled.
- PM-WANI systems own protocol/session outcomes and registry state. Store only the permitted minimum references/audit data in business systems.
- Zabbix owns metrics and alert history. Odoo/NMS tickets can refer to a Zabbix problem ID.
- Every synchronized record needs an external ID, source-of-truth rule, direction, conflict rule, and retry policy. No direct cross-system database reads/writes.

## 5. Key workflows

### Customer to activated service

1. A lead enters Odoo through staff or an approved website form.
2. Staff qualify it and create a customer/service request.
3. An Odoo-to-NMS connector creates or updates the subscriber/service using an idempotency and correlation ID.
4. NMS Prime returns stable identifiers and provisioning state; Odoo displays status and exposes failures for retry or resolution.
5. Confirmed activation can trigger a customer notification through n8n.

### PM-WANI access

1. Confirm whether the company operates as App Provider, PDOA, PDO, or uses another authorized provider.
2. The Flutter app uses the mobile API for registration/login and the agreed discovery journey.
3. The PM-WANI adapter performs the prescribed authentication/token flow and PDOA interaction. Long-lived credentials are never exposed to the app.
4. Record correlation ID, timestamp, outcome, and permitted audit data; never log secrets or full tokens.
5. Treat payment status, WANI authorization, and accounting reconciliation as distinct events.
6. Make current certification test cases and required approvals release gates.

DoT describes separate PDO, PDOA, App Provider, and Central Registry roles; the App Provider process includes deployed software, security configuration, provisional certification, and software certification. C-DOT's test plan explicitly tests the waniapptoken flow. See [DoT PM-WANI authorization](https://www.eservices.dot.gov.in/pm-wani-service-authorisation), [App Provider process](https://eservices.dot.gov.in/app-provider), [PDOA role](https://www.eservices.dot.gov.in/public-data-office-aggregator-pdoa), and [C-DOT test plan](https://eservices.dot.gov.in/sites/default/files/2024-11/PMWANI-AppProvider-TSTP-Plan-v01.pdf).

### Support

Customer app, email, or approved website channels create an Odoo ticket with customer/service references. The ticket links to relevant NMS identifiers and Zabbix problem IDs. Support owns communication and case closure; network staff own remediation in NMS. Customer status notifications are asynchronous.

### Finance and statutory reporting

Reconcile sales/service and payment events into the selected Odoo accounting design. At period close, validate tax mappings, invoices, credit/debit notes, receipts, and exceptions. Produce a period-stamped GST data pack for accountant review. Track applicable ISP/DoT obligations, preparer/reviewer, due date, status, and evidence. Direct portal filing is a later, separately authorized integration.

GST's official GSTR-1 guide lists portal, offline-tool, and ASP-through-GSP preparation routes. DoT's ISP License Agreement has service-specific accounting/reporting conditions; the company must confirm the applicable obligations. See [GST GSTR-1 guidance](https://tutorial.gst.gov.in/userguide/returns/GSTR_1.htm) and [DoT ISP License Agreement](https://www.eservices.dot.gov.in/sites/default/files/2024-11/ISP%20License%20Agreement.pdf).

### Daily website and social content

Maintain a calendar with channel, date, audience, approved factual sources, and owner. AI drafts copy; a human approves factual claims, offers, and visuals. n8n publishes through supported CMS/social APIs and records result IDs/errors. AI may recommend advertising changes; ad spend changes require explicit human approval.

## 6. Interfaces

| Path | Contract and controls |
|---|---|
| Flutter to mobile API | Versioned HTTPS JSON endpoints; rate limiting, authorization, session revocation, input validation; no embedded secrets |
| Mobile API to Odoo | Narrow business endpoints supported by the chosen self-hosted Odoo version; least-privilege bot identity, audit, idempotency |
| Odoo to NMS Prime | Vendor-supported API/extension; asynchronous provisioning commands, correlation IDs, bounded retry and manual exception queue |
| PM-WANI adapter to Registry/PDOA | Exact current role-specific interface, certificates, endpoints, token format, and test plan; direct synchronous path where required |
| n8n to business systems | Webhooks/narrow APIs; unique credentials per workflow, retries, execution-data limits, restricted nodes and audit |
| Zabbix to alerts | Agreed severity mapping, deduplication, escalation and notification route; avoid PII in alert payloads |
| Website/social | Supported CMS and official platform APIs; per-channel credentials, human approval, rate-limit handling |
| GitHub to environments | Reviewed CI/CD with protected environments and managed deployment secrets |

Odoo's API availability differs by deployment/version. The Odoo 19 external API docs describe JSON-2 and API-key controls; hosted plan limits also apply. Prove the integration method against the selected self-hosted Community release before committing. For Community helpdesk, evaluate a maintained compatible implementation such as [OCA/helpdesk](https://github.com/OCA/helpdesk), including branch, dependencies, license, and maintenance. See [Odoo 19 API](https://www.odoo.com/documentation/19.0/developer/reference/external_api.html) and [Odoo 20 JSON-2 API](https://www.odoo.com/documentation/20.0/developer/reference/external_api.html).

## 7. Hosting and operations

Use separate development, staging, and production environments with isolated credentials:

- Public edge: DNS, TLS, reverse proxy/WAF, rate limiting and routing.
- Odoo: application service, private PostgreSQL database, controlled document storage and outbound mail.
- Mobile: independent API service; app/session/cache store only for data not owned by Odoo or NMS.
- Integration: PM-WANI adapter, NMS connector, n8n with its own database and bounded execution-data retention. Use an outbox/queue for business events requiring replay.
- Monitoring: Zabbix server/database and optional regional proxies. Keep management interfaces private.
- Recovery: encrypted, access-controlled backups stored separately from production; periodic restore exercises.
- Delivery: GitHub and CI/CD with secrets in a managed secret store, never in source or mobile bundles.

Zabbix separates server, database, web interface, proxies, and agents; proxies can distribute collection. See [Zabbix 8.0 concepts](https://www.zabbix.com/documentation/8.0/en/manual/concepts). n8n supports self-hosting and provides a configuration/credential/node/webhook security audit; this supplements rather than replaces a security review. See [n8n docs](https://docs.n8n.io/) and [n8n security audit](https://docs.n8n.io/hosting/securing/security-audit/).

## 8. Security and privacy

- TLS on all network paths; private service networking and firewall allow-lists.
- Role-based access, MFA for staff administration, least-privilege service identities, credential rotation, and emergency revocation.
- No public Odoo, NMS, Zabbix, or n8n administration routes.
- Store secrets in managed runtime configuration. Never put WANI tokens, API keys, payment credentials, or private certificates in GitHub, mobile binaries, analytics, or ordinary logs.
- Minimize personal data in app stores, events, alerts, and workflow history. Set retention/deletion rules with the compliance owner.
- Audit financial report runs/approvals, privilege changes, filing evidence, and integration actions.
- Alert on failed provisioning, token/certificate expiry, queue backlog, repeated workflow failure, capacity, backups, and service availability.
- Agree service levels, recovery objectives, support coverage, and load envelope during discovery; none are assumed here.

## 9. Discovery exit decisions

1. NMS Prime product/version, supported API, sandbox, data export rights, topology, and vendor owner.
2. Odoo version, hosting, Community-compatible CRM/HR/helpdesk/accounting modules, India localization, licenses, upgrades, and API proof.
3. PM-WANI role, Registry access, current protocol/test plan, certificates, endpoint ownership, and certification responsibilities.
4. GSTIN count, accountant-approved report layouts, GSP/API decision, and authorization-specific ISP/DoT reporting.
5. App audience, identity/OTP provider, operating systems/languages, MVP flows, payments and notifications.
6. CMS, social channels, brand rules, AI provider/data policy, and content approval roles.
7. Hosting region/provider, expected subscriber scale, HA/DR, support hours, and operating cost.

## 10. References

- [DoT PM-WANI authorization](https://www.eservices.dot.gov.in/pm-wani-service-authorisation), [App Provider process](https://eservices.dot.gov.in/app-provider), [PDOA role](https://www.eservices.dot.gov.in/public-data-office-aggregator-pdoa), and [C-DOT test plan](https://eservices.dot.gov.in/sites/default/files/2024-11/PMWANI-AppProvider-TSTP-Plan-v01.pdf)
- [GST GSTR-1 guide](https://tutorial.gst.gov.in/userguide/returns/GSTR_1.htm) and [DoT ISP License Agreement](https://www.eservices.dot.gov.in/sites/default/files/2024-11/ISP%20License%20Agreement.pdf)
- [Odoo 19 external API](https://www.odoo.com/documentation/19.0/developer/reference/external_api.html), [Odoo 20 JSON-2 API](https://www.odoo.com/documentation/20.0/developer/reference/external_api.html), and [OCA Helpdesk](https://github.com/OCA/helpdesk)
- [n8n security audit](https://docs.n8n.io/hosting/securing/security-audit/) and [Zabbix 8.0 concepts](https://www.zabbix.com/documentation/8.0/en/manual/concepts)

