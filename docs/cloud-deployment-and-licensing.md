# OMISHA NETWORK OS: cloud and licensing design

Status: development foundation, 10 November 2026. This repository does not yet implement the complete ISP platform or a production cloud service.

## Cloud model

OMISHA operates the central cloud account and controls source repositories, build pipelines, a private image registry, an administrative control plane, monitoring, and backup storage. The existing public GitHub repository is a source mirror; the production source repository and registry should be access-controlled. Client users access the platform over HTTPS. Customers do not need to host source code.

Deploy each client as an isolated Frappe site with its own database, site files, secrets, tenant identity, and backup/restore policy. Run shared platform services only where tenancy is explicitly enforced. For larger clients, support separate worker pools, database instances, or environments. NMS Prime deployment and integration remain subject to its supported installation model and real API: do not claim the existing Rocky installer is Docker-ready.

Per tenant: ERPNext, Frappe CRM, Helpdesk, HR, and India Compliance need a tested compatibility matrix and custom Frappe image. Use the official Frappe Docker production compose/overrides and custom-image build process; the official single-file demo is not a production deployment. Zabbix, n8n, app API, PM-WANI, and NMS adapters require separately configured services and integrations. Zabbix uses a supported SQL database. Treat this repository's compose file as a licensing component demonstration only.

For scaling: stateless web/API and worker replicas can scale after ensuring app-level session, scheduler, and queue coordination; persistent databases, shared site files, backups, ingress, and monitoring need their own HA design. Docker Compose on one host is not highly available. Pick cloud provider, region, resource sizing, target RPO/RTO, recovery tests, and network topology before production.

## Per-client, per-user licensing

Each signed license is bound to a tenant ID and installation ID and has an expiry, feature list, and maximum active named users. Default policy proposal: active named staff accounts consume seats; disabled accounts and customer portal identities do not. The policy needs a final business decision and must be implemented consistently in Frappe and the cloud control plane.

For online subscription, the planned OMISHA license authority should authenticate activation codes, maintain subscriptions, handle renewals/revocations and seat allocation in a transactional database, sign short-lived license assertions, audit actions, rate-limit endpoints, and support key rotation. The included client defines a narrow HTTPS activation request: POST JSON tenant_id and installation_id with a bearer activation code; receive a signed envelope matching payload.example.json. This repository does not yet provide that authority, billing, renewal, revocation, activation-code lifecycle, or remote device management.

For offline/perpetual licensing, issue a signed license on a controlled issuer workstation and transfer only the license and public key to the installation. Set an expiry that corresponds to the agreed entitlement; a perpetual policy and format are not yet implemented. Offline validity depends on an accurate trusted clock. Signing keys must be stored off the client, protected by an appropriate secret-management/KMS process, and rotated through a versioned trust mechanism before production.

The verifier can check a supplied active-user count against max_users. It is not yet connected to Frappe user creation, login, user disablement, feature access, or a centralized transactional seat ledger. It therefore does not enforce per-user limits. Concurrent seat assignment, atomic updates, roles, portal-user policy, grace periods, clock rollback, revocation, tenant provisioning/deletion, privacy, and billing disputes need implementation and security review.

## Local development example

Use Python 3.12 and install licensing/requirements.txt in a virtual environment. The following commands use placeholder IDs and create a real signing key locally. Never commit or upload the private key.

    python licensing/omisha_license.py keygen --private-key issuer-private.pem --public-key public.pem
    python licensing/omisha_license.py issue --private-key issuer-private.pem --payload licensing/payload.example.json --output example.license.json
    python licensing/omisha_license.py verify --public-key public.pem --license example.license.json --tenant example-client --installation example-installation --active-users 10

The online activation client is available with the activate subcommand. It requires a separately implemented HTTPS authority conforming to the contract above. It validates the returned signature, time, tenant, and installation before saving. It does not send the private signing key.

For the local Compose demo, copy .env.example to .env, create runtime/, place the public key at runtime/public.pem and signed license at runtime/license.json, then run docker compose up --build. The verifier listens only on host loopback port 9080. GET /health indicates the process is alive; GET /license reports signature status. Neither endpoint establishes that user seats are enforced or that any ERP service is running.

## Deployment prerequisites

- Cloud provider/account, region, DNS/domain, access and budget; source/repository and container-registry hosting policy.
- Exact NMS Prime version, supported integration and cloud deployment model; existing data migration plan.
- Pinned compatible Frappe, ERPNext, CRM, Helpdesk, HR and India Compliance releases and licensing terms.
- Customer counts, peak concurrent users, tenant isolation tier, support hours, backup/restore and uptime targets.
- Per-user seat definition, billing period, grace period, offline/perpetual policy, and signing-key custody.
- PM-WANI operator role, provider interface, certificate ownership, and certification path.

Sources: [Frappe Docker](https://github.com/frappe/frappe_docker), [Frappe deployment methods](https://github.com/frappe/frappe_docker/blob/main/docs/01-getting-started/01-choosing-a-deployment-method.md), [Docker Compose startup order](https://docs.docker.com/compose/how-tos/startup-order/).

