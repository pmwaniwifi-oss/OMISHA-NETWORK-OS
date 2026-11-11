import json
import re

import frappe
from frappe import _
from frappe.model.document import Document


class ISPAcquisitionRequest(Document):
    def validate(self):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{7,127}", self.idempotency_key or ""):
            frappe.throw(_("Idempotency Key must contain 8–128 safe characters."))

        previous = self.get_doc_before_save()
        guarded_fields = (
            "identity_status",
            "verification_reference",
            "consent_policy_version",
            "consent_recorded_at",
            "acquisition_status",
            "sales_order",
            "service_order",
        )
        immutable_after_submit = (
            "channel",
            "lead",
            "requested_plan",
            "service_address",
            "assigned_technician",
            "identity_method",
            "consent_recorded",
            "consent_method",
            "consent_reference",
        )
        if self.is_new() and (
            self.identity_status != "Not Started"
            or self.acquisition_status != "Draft"
            or self.consent_recorded
            or self.verification_reference
        ):
            frappe.throw(_("New acquisition requests must begin in an unverified Draft state."))
        if previous:
            if self.idempotency_key != previous.idempotency_key:
                frappe.throw(_("Idempotency Key cannot change after creation."))
            if previous.docstatus == 1 and any(self.get(field) != previous.get(field) for field in immutable_after_submit):
                frappe.throw(_("Submitted acquisition details and consent receipt cannot be edited."))
            if any(self.get(field) != previous.get(field) for field in guarded_fields):
                if not getattr(frappe.flags, "omisha_acquisition_projection_update", False):
                    frappe.throw(_("Verification and workflow fields can only be changed by a trusted server-side integration."))

        if self.channel == "Technician Assisted":
            if not self.assigned_technician:
                frappe.throw(_("Assign a technician for technician-assisted registration."))
            if not frappe.db.get_value("User", self.assigned_technician, "enabled"):
                frappe.throw(_("Assigned technician must be an enabled user."))
            if "ISP Technician" not in frappe.get_roles(self.assigned_technician):
                frappe.throw(_("Assigned user must have the ISP Technician role."))
        elif self.assigned_technician:
            frappe.throw(_("Customer self-service requests cannot be assigned to a technician at creation."))

        if not frappe.db.exists("Lead", self.lead):
            frappe.throw(_("Lead must exist in this client site."))
        if not frappe.db.exists("Item", self.requested_plan):
            frappe.throw(_("Requested plan must exist in this client site."))
        if not frappe.db.exists("Address", self.service_address):
            frappe.throw(_("Service address must exist in this client site."))
        linked_address = frappe.db.exists("Dynamic Link", {
            "parenttype": "Address",
            "parent": self.service_address,
            "link_doctype": "Lead",
            "link_name": self.lead,
        })
        if not linked_address:
            frappe.throw(_("Service address must be linked to this Lead."))

        if self.verification_reference and len(self.verification_reference) > 140:
            frappe.throw(_("Verification reference is too long. Store a reference only, never raw identity data."))

    def before_submit(self):
        if not self.consent_recorded or not self.consent_reference:
            frappe.throw(_("A consent receipt must be recorded before submission."))
        if self.identity_method == "Not Selected":
            frappe.throw(_("Select an approved identity verification method before submission."))
        if self.channel == "Customer Self-Service" and self.consent_method != "Electronic Self-Service":
            frappe.throw(_("Self-service requests require electronic customer consent."))
        if self.channel == "Technician Assisted" and self.consent_method not in {
            "Technician-Assisted Electronic",
            "Other Approved Method",
        }:
            frappe.throw(_("Technician-assisted requests require an approved consent method."))
        if not frappe.conf.get("omisha_consent_policy_version"):
            frappe.throw(_("Configure omisha_consent_policy_version before accepting onboarding consent."))

    def on_submit(self):
        # The event shares this transaction and contains no customer or identity payload.
        event = frappe.get_doc({
            "doctype": "ISP Integration Event",
            "event_type": "acquisition.submitted",
            "source_doctype": self.doctype,
            "source_name": self.name,
            "idempotency_key": "acquisition:" + self.name + ":submitted",
            "payload_json": json.dumps({
                "schema": "isp.acquisition.submitted.v1",
                "acquisition_request": self.name,
            }, sort_keys=True, separators=(",", ":")),
            "status": "Pending",
        })
        event.insert(ignore_permissions=True)
        self.db_set("consent_policy_version", frappe.conf.get("omisha_consent_policy_version"), update_modified=False)
        self.db_set("consent_recorded_at", frappe.utils.now_datetime(), update_modified=False)
        self.db_set("acquisition_status", "Serviceability Review", update_modified=False)
