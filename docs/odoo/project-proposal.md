# NMS Prime + Odoo Community platform

## Project proposal

**Prepared:** 6 October 2026  
**Status:** Planning proposal; discovery is required before fixed scope or price  
**Related document:** [Technical architecture](technical-architecture.md)

## 1. Executive summary

Connect sales, customer support, HR, finance/compliance, ISP operations, customer mobile services, monitoring, and digital marketing in one managed platform.

Odoo Community provides business workflows. NMS Prime remains the network/subscriber operations platform. A separate backend serves the Flutter customer app. Dedicated connectors integrate NMS Prime and the applicable PM-WANI role. Zabbix monitors systems, GitHub manages source/releases, and n8n automates reviewed non-critical workflows.

The first project phase resolves four major constraints: NMS Prime interface availability, Odoo Community module fit, PM-WANI role/certification requirements, and statutory report definitions.

## 2. Objectives

- Connect lead, customer, activation, and support lifecycles.
- Digitize selected HR and staff workflows.
- Produce finance and compliance data packs with review history and filing evidence.
- Provide a customer Flutter app with an independently hosted API backend.
- Implement the PM-WANI flow required for the company's actual role and support technical certification.
- Monitor agreed applications, servers, network collection points, and integration health in Zabbix.
- Automate approved internal workflows and human-reviewed daily website/social content.
- Manage custom source and releases through GitHub.

## 3. Proposed scope

### Included

1. **Discovery and fit-gap:** process workshops, module/version inventory, interface and data ownership map, compliance/report register, app MVP, deployment/security requirements.
2. **Odoo Community:** CRM, customer/service references, selected HR workflows, accounts/invoice configuration, helpdesk through an approved Community-compatible module, access roles.
3. **Finance/compliance outputs:** accountant-reviewed GST data packs and a configurable ISP/DoT compliance calendar/evidence register. Initial scope prepares reports; it does not file returns unattended.
4. **NMS Prime integration:** agreed customer/service cross-references, provisioning/status exchange, support links, retry and exception handling.
5. **PM-WANI:** role-specific adapter, app authentication/token flow, security configuration, test evidence, and certification coordination. Company authorization and external Registry/lab decisions remain with the company.
6. **Flutter app:** proposed initial customer scope includes sign-in, customer/service overview, support request/status, approved service discovery and PM-WANI interaction where relevant, notifications, and privacy/consent screens.
7. **n8n and marketing:** workflow deployment, selected notifications/approvals, daily content calendar, AI-assisted drafts, and staff-approved website/social publication.
8. **Zabbix and GitHub:** agreed monitoring, repositories, review/deployment workflow, staging, production release and rollback process.
9. **Handover:** training, runbooks, API/interface documentation, backup/restore and ownership transfer.

### Not included in the initial release

- Rebuilding NMS Prime or creating a new billing/provisioning engine without separate approval.
- Legal advice, audit sign-off, determining statutory obligations, or automatic GST filing.
- Obtaining company authorizations, Registry registration, payment underwriting, or external certification on the company's behalf; technical preparation and coordination are included.
- Full payroll/statutory HR automation before module and local compliance review.
- AI publishing regulated claims without approval or changing paid advertising budgets.
- 24/7 managed operations, new network hardware, app-store fees, third-party licenses, cloud/provider charges, or paid communications APIs.

## 4. Odoo Community module decision

Community Edition remains the target, subject to release-specific fit-gap. CRM is a candidate for the core. Helpdesk, accounting/GST, payroll, and some HR functions must be checked against the selected Community release and module license/support status.

Evaluate Odoo Community Association helpdesk modules or another explicitly approved Community-compatible implementation. Confirm branch maturity, dependencies, upgrade path, security history, India localization, and maintenance before selection. If official Odoo Enterprise Helpdesk or unavailable finance/HR features are required, make the cost/scope decision before build. Verify the exact API method supported by the selected self-hosted version.

## 5. Delivery plan

Planning range: **approximately 20–28 weeks elapsed** from kickoff to initial production release, assuming timely access to system owners, sandbox credentials, report reviewers, and interface specifications. Workstreams can overlap after architecture and interface contracts are approved. Certification schedules, external approvals, vendor response, and app-store review can extend the timeline.

| Phase | Indicative duration | Main outputs | Exit decision |
|---|---:|---|---|
| 0. Discovery and fit-gap | 2–3 weeks | Confirmed workflows, Odoo module/version matrix, compliance/report register, interface inventory, app MVP, security/hosting decisions, refined estimate | Approve scope and architecture |
| 1. Foundation | 2–3 weeks | Environments, GitHub/release controls, roles, backup plan, Odoo baseline, Zabbix/n8n foundations | Environment/security review |
| 2. Business core | 4–6 weeks | CRM, customer/service links, selected HR/helpdesk, finance configuration and reports | Business-owner walkthrough |
| 3. Network and PM-WANI | 4–8 weeks | NMS connector, PM-WANI adapter, audit/retry paths, test/certification evidence | Protocol and certification gate |
| 4. Mobile and automation | 5–8 weeks | Flutter app, dedicated API, n8n approvals/notifications, website/social workflow | Product/security review |
| 5. UAT and handover | 2–3 weeks | Data reconciliation if needed, UAT, training, runbooks, production release | Business sign-off |

These ranges are planning estimates, not a fixed bid. Phase 0 validates module availability, API access, migration volume, user counts, hosting, operating targets, and certification dependencies.

## 6. Team and governance

Recommended owners: executive sponsor; product owner; NMS/network operations owner; finance/tax reviewer; HR owner; support lead; mobile product owner; solution architect; Odoo functional/development lead; integration/backend developer; Flutter developer; infrastructure/security engineer; QA/UAT coordinator; PM-WANI/C-DOT/vendor contact.

Hold a weekly delivery review for decisions, dependencies, risks, change requests, and demonstrations. Each functional owner approves their own process and reports. Production changes require a named approver and rollback owner.

## 7. Commercial estimate structure

No fixed project price is proposed because subscriber/user counts, API access, migration volume, module selection, hosting, report count, app features, and support coverage are unknown. After discovery, estimate implementation, Odoo modules, integrations, mobile/API, migration, security review, certification preparation, licenses, hosting/communications, training, warranty, and ongoing support separately.

Compare total operating cost and upgrade effort for a Community-first design against any Enterprise components needed to meet the approved scope.

## 8. Production acceptance

- Agreed CRM, customer, HR, ticket, finance, and compliance workflows work with role-based access.
- Odoo and NMS Prime maintain stable cross-references and visible retry/exception handling.
- Flutter uses only the dedicated API; no Odoo/NMS credentials or database access are in the client.
- PM-WANI follows the confirmed role-specific interface; secrets/tokens are absent from ordinary logs; required technical tests have recorded evidence and external approval.
- GST outputs reconcile against accountant-approved sample periods and preserve reviewer/period/version records.
- ISP/DoT calendar reflects obligations verified for the company's authorization; filing evidence is traceable.
- Zabbix alerts on agreed service conditions and a backup restore is demonstrated.
- AI content cannot publish without human approval; ad spend cannot be changed by AI alone.
- GitHub source, deployment instructions, and a release/rollback record are complete.
- Business owners sign UAT and operations/support staff receive runbooks and training.

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| NMS Prime lacks a supported API or sandbox | Obtain vendor interface pack in discovery; prove one read and one write flow before full commitment |
| Community module gap for helpdesk/accounts/HR | Lock release/module/license matrix; prototype critical workflows; decide Community vs Enterprise before build |
| PM-WANI role or certification is unclear | Confirm role, current token/interface contracts, access, certificates, test plan, and lab schedule with DoT/C-DOT/provider |
| GST/ISP obligations are misinterpreted | Have the company's CA and authorized telecom compliance owner approve output definitions and evidence requirements |
| Duplicated customer/network data diverges | Define record ownership, shared fields, stable IDs, and reconciliation |
| API/payment/social provider changes | Use versioned adapters, dependency register, monitoring, credential rotation, and rollback |
| AI produces inaccurate claims or publishes unexpectedly | Human approval, approved facts, audit trail, channel permissions, no autonomous budget changes |
| Recovery/capacity needs are underestimated | Size after volume discovery; agree targets and exercise restore |

## 10. Decisions to finalize

1. Is the mobile app customer-facing, staff-facing, or both?
2. What are NMS Prime product/version and vendor/API details?
3. What PM-WANI role does the company hold or intend to use? Is Registry/provider/test access available?
4. Which Odoo Community release is preferred, and are OCA/third-party modules acceptable?
5. How many GSTINs and which accountant-approved outputs and ISP/DoT obligations are required?
6. Which CMS/social channels and who approves daily content? May AI draft only, or publish after approval?
7. Approximate subscribers, monthly tickets, staff users, locations, data volume, and hosting region?
8. Target launch date, support hours, and recovery expectations?

## 11. Official technical references

The [technical architecture](technical-architecture.md) includes official DoT PM-WANI pages and C-DOT test plan, GST Portal GSTR-1 guide, DoT ISP License Agreement, Odoo API docs, OCA Helpdesk project, n8n security audit, and Zabbix architecture references.

