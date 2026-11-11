# OMISHA ISP Operations for Frappe

Initial app scope: customer service orders and transactional integration outbox.
Install on a dedicated client Frappe site only after building/pinning a custom
ERPNext image containing this app. This app does not yet expose public APIs or
connect to a live NMS server.

## Event behavior

Submitting an ISP Service Order inserts one ISP Integration Event in the same
Frappe database transaction. The event has a stable unique idempotency key and a
small, validated payload containing only the Service Order reference. Frappe's transaction
rollback then removes both the order submission and event, avoiding a partial
cross-system write. A future worker can lease pending events, call the read/write
NMS adapter only after separate approval, and mark success/failure with retry
metadata. No worker, network call or automatic provisioning is implemented yet.

## Tenant boundary

The app relies on the deployment boundary: one client per Frappe site/Compose
project/database. A link to a Customer is checked against the current site. This
does not replace user authentication, role permission review or API-level
authorization. Do not add client IDs to requests as a security boundary.

## Install in a disposable site

After the custom image includes the app, install it with `bench --site <site>
install-app omisha_isp` inside the private Frappe backend container. Back up and
restore-test the site first. Never run a schema migration against a real site
without a tested recovery point. The repository's stock ERPNext image does not
include this custom app yet.

## Current limitations

- No NMS provisioning, PM-WANI, billing, GST, login, seat licensing or approval UI.
- No outbox worker, dispatch, retry scheduler, tenant-sharing or public API.
- The outbox payload is an internal database record; it is not a signed audit log.
- DB level unique key prevents duplicate outbox records; it cannot guarantee an
  exactly-once effect at NMS. Future consumers must be idempotent and reconcile.
