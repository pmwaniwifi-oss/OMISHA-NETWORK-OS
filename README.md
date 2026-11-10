# OMISHA NETWORK OS

Project planning and installer draft for an integrated ISP platform.

## Current status

- `docs/frappe/`: ERPNext/Frappe integration architecture and performance proposal. This is the recommended business-platform direction.
- `docs/odoo/`: earlier Odoo Community architecture, project proposal, and development backlog. These are alternative planning documents, not an implemented integration.
- `installer/carrier-core-draft.sh`: previously prepared Carrier Core installer draft integrating NMS Prime and PostgreSQL. It has received static checks only and has not been validated by a Linux installation or end-to-end deployment. Review its prerequisites, credentials handling, and external downloads before use.

The Frappe and Odoo designs are alternative tracks. CRM, helpdesk, HR, accounts, GST, ISP reporting, PM-WANI, Flutter, Zabbix, and n8n remain subject to the integration work and validation described in the documents. PM-WANI certification and statutory reporting requirements depend on the operator's role and authorizations.

## Proposed direction

NMS Prime manages network/subscriber operations; ERPNext and the Frappe ecosystem manage business workflows; Zabbix provides monitoring; a dedicated API serves a Flutter app; PM-WANI uses a role-specific adapter; and n8n handles approved asynchronous workflows. Pin compatible component versions and verify NMS interfaces before implementation.

