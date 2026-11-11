# OMISHA ISP Operations for Frappe

Initial source foundation: ISP acquisition request, service order, and transactional integration outbox. Install only on a dedicated client Frappe site after building and pinning a custom ERPNext image containing this app. No public customer API or live NMS/payment/identity adapter is included.

## Acquisition request

The ISP Acquisition Request is a shared record for customer self-service and technician-assisted intake. It links to the ERPNext Lead, plan Item, and Address rather than copying their profile/address data. Technician-assisted intake also links an assigned user with the ISP Technician role. Submitting creates a small outbox event in the same transaction containing only the acquisition request reference and schema version.

Consent must be recorded with a receipt reference, selected method, and configured `omisha_consent_policy_version` before submission. The submitted acquisition and consent fields are locked. Verification status and workflow projections are server-controlled. This is an intake data model, not proof that the selected Aadhaar or other identity method is legally approved or technically verified.

The fields intentionally do not hold Aadhaar numbers, raw QR/XML/e-Aadhaar artifacts, OTPs, biometrics, payment credentials, or identity document images. The request may link to one ERPNext Payment Request; it does not copy provider transaction data or payment status. ERPNext Payment Request/Payment Entry remain the payment source of truth. No payment is accepted or confirmed by this app. No service is provisioned or activated.

## Service-order event behavior

Submitting an ISP Service Order inserts one ISP Integration Event in the same Frappe database transaction. Its stable idempotency key and bounded payload contain only the Service Order reference. A future worker may process it only after a reviewed integration contract. No worker, network call, payment, identity verification, or automatic NMS provisioning is implemented.

## Tenant boundary

The app relies on deployment isolation: one client per Frappe site/Compose project/database. Links resolve only inside the current site. This does not replace user authentication, role permission review or API-level authorization. Tenant identity comes from the authenticated deployment connection, not a client-provided request field.

## Install in a disposable site

After a custom image includes the app, install it with `bench --site <site> install-app omisha_isp` inside the private Frappe backend container. Back up and restore-test the site first. Never run a schema migration against a real site without a tested recovery point. The stock ERPNext image does not include this custom app.

## Current limitations and release gates

- The app has not been installed or integration-tested against a Frappe site.
- No customer self-service or technician-facing API/UI, authentication flow, identity-verification adapter, payment provider, refund/reversal flow, NMS provisioning, PM-WANI, GST setup, seat licensing, or approval UI.
- No outbox worker, dispatch, retry scheduler, or reconciliation job.
- DoT/UIDAI requirements and consent policy must be confirmed for the operator's actual authorization and identity method before use.
- `omisha_consent_policy_version` must be set to the approved policy version. A consent reference/checkbox alone does not perform or prove legal identity verification.
- A unique database key prevents duplicate outbox rows; it cannot guarantee exactly-once external effects. Future consumers must be idempotent and reconcile.
