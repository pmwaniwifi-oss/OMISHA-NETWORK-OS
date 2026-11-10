# OMISHA NETWORK OS

Project planning and installer draft for an integrated ISP platform.

## Current status

- [Phase 1 implementation](docs/implementation-phase-1.md): read-only environment preflight, hardened license validation/readiness, automated checks and a tested lossless log archive utility.
- [ISP log storage policy](docs/log-storage-policy.md): preserve complete records with Zstandard compression and exact-byte recovery verification; no automatic deletion or compliance certification.

- `docs/cloud-deployment-and-licensing.md`: proposed OMISHA-hosted, per-client cloud and per-user licensing design.
- `licensing/` and `docker-compose.yml`: development foundation for signed offline license verification and an online activation client. This does not yet enforce Frappe user seats or implement an online license authority. Compose runs only the licensing component, not the full platform.
- `edge/`: local VM prototype with a Go gateway, Rust worker, and Valkey cache in separate containers. Customer APIs, authentication, NMS/ERP integrations, and actual background jobs are not implemented; it must not be exposed to the internet.
- `docs/verification-status.md`: current checks and unresolved gaps.

- `docs/frappe/`: ERPNext/Frappe integration architecture and performance proposal. This is the recommended business-platform direction.
- `docs/odoo/`: earlier Odoo Community architecture, project proposal, and development backlog. These are alternative planning documents, not an implemented integration.
- `installer/carrier-core-draft.sh`: previously prepared Carrier Core installer draft integrating NMS Prime and PostgreSQL. It has received static checks only and has not been validated by a Linux installation or end-to-end deployment. Review its prerequisites, credentials handling, and external downloads before use.

The Frappe and Odoo designs are alternative tracks. CRM, helpdesk, HR, accounts, GST, ISP reporting, PM-WANI, Flutter, Zabbix, and n8n remain subject to the integration work and validation described in the documents. PM-WANI certification and statutory reporting requirements depend on the operator's role and authorizations.

## Proposed direction

NMS Prime manages network/subscriber operations; ERPNext and the Frappe ecosystem manage business workflows; Zabbix provides monitoring; a dedicated API serves a Flutter app; PM-WANI uses a role-specific adapter; and n8n handles approved asynchronous workflows. Pin compatible component versions and verify NMS interfaces before implementation.

