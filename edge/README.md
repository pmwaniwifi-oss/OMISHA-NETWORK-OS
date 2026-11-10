# OMISHA customer edge: development scaffold

This Compose project contains separate Go gateway, Rust worker, and Valkey containers. The gateway listens only on the VM's loopback port 8088; Valkey is on an internal network with no published port. Valkey is configured as a disposable cache: data can be evicted or lost and must never be the only record of invoices, licenses, provisioning jobs, or payments.

Run on a Linux VM with a working Docker engine:

    docker compose -f edge/docker-compose.yml up --build
    curl http://127.0.0.1:8088/healthz
    curl http://127.0.0.1:8088/readyz

The Rust worker currently checks Valkey connectivity only. Customer endpoints deliberately return HTTP 501. NMS and ERP connections, authentication, per-client access isolation, TLS ingress, per-user licensing enforcement, actual cache policies, durable job handling, rate limiting, metrics, and deployment monitoring are not implemented. Do not expose this scaffold to customers or the internet.

For the intended design, customer apps connect over HTTPS to a gateway/BFF that validates identity, tenant, license, and authorization. The gateway uses narrowly scoped integrations with NMS Prime and Frappe APIs; neither database is exposed. Cache keys must include tenant and authorization scope, use bounded TTLs and explicit invalidation, and avoid storing secrets. Durable jobs require an authoritative database/outbox and idempotent processing; a cache eviction must not lose billing or provisioning requests.

Build and deployment remain separate from the official Frappe and NMS deployments until their real interfaces, versions, and supported installation modes are identified. Establish measured p50/p95 latency, throughput, error rate, cache hit rate, and resource baselines before claiming speed improvements or increasing replica counts. A single VM is not highly available.

