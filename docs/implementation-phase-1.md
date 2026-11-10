# Phase 1: verifiable foundation

Baseline: `a97c16cd3f4070b57fb4888fff58f8e78824593c`.
Canonical direction: NMS Prime for network operations, ERPNext/Frappe for the
back office, narrow Go integration/API services, optional measured Rust work,
and disposable Valkey caches. Odoo remains an alternative proposal.

## Implemented in this change

- Read-only `scripts/preflight.py`: distinguishes an available CLI from a
  reachable Docker daemon, checks actual compiler version output, and reports
  only the current execution environment. It never reads runtime secrets.
- Licensing rejects ambiguous JSON, oversized inputs, invalid UTC times,
  duplicate features and invalid seat-count types. Optional `verify --feature`
  checks a signed feature. This is not an atomic user-seat ledger.
- `/health` remains process liveness; `/readyz` verifies the installed signed
  entitlement. Compose health now uses readiness. Invalid/missing entitlement
  cannot report healthy just because the process is alive.
- Container resource limits on the licensing prototype; no public ports added.
- Automated Python/Go checks and actual container build/connectivity checks in
  GitHub Actions. Actions are SHA-pinned; current base image tags are inherited
  from the baseline and must pass the build job. Image digest locking and a
  validated full component matrix remain release gates.
- Lossless Zstd closed-log archive utility and its corruption/tenant tests;
  see [log storage policy](log-storage-policy.md).

## Reproduce local checks

```bash
python -m pip install -r licensing/requirements.txt -r logging/requirements.txt
python -m unittest discover -s licensing -p 'test_*.py' -v
python -m unittest discover -s scripts -p 'test_*.py' -v
python -m unittest discover -s logging -p 'test_*.py' -v
python scripts/preflight.py
```

Inside the actual laptop Linux VM, `python scripts/preflight.py --require-docker`
exits nonzero if Docker Engine or Compose is unavailable. No package installation
or service start is attempted by preflight. A successful inventory is not ERP/NMS
acceptance. Docker builders provide the language compilers; host Go/Rust are not
required merely to run prebuilt containers.

Local verification: 21 licensing tests, 4 preflight tests and 10 archive tests
pass with Python 3.12, cryptography 50.0.0 and zstandard 0.25.0. The project's
cryptography 45.0.6 pin is exercised by CI, not by that local result. Docker,
usable Go and Rust toolchains are unavailable in this execution environment.
CI results are separate evidence; do not assume success from workflow existence.

## Next deliverables and dependencies

1. Prove image builds/VM inventory and pin a compatible Frappe app set.
2. Transactional tenant/seat ledger, online authority and Frappe enforcement.
3. Tenant-scoped identity and Go API contracts; no custom identity protocol.
4. ERP service-order outbox and NMS adapter against the real supported API.
5. Reconciled activation-to-invoice vertical slice and mobile API.
6. Durable log ingest, searchable projections, independently protected archives,
   verified export and retention/hold controls. No automatic legal-log deletion.

No legacy installer is executed by the workflow. No production deployment,
NMS/ERP integration, government certification or measured ISP capacity is claimed.
