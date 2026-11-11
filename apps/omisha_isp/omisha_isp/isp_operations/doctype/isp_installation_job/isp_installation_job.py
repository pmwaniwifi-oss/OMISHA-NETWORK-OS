import json
import re

import frappe
from frappe import _
from frappe.model.document import Document


class ISPInstallationJob(Document):
    def validate(self):
        if self.is_new():
            if self.completed_at:
                frappe.throw(_("A new installation job cannot have a completion timestamp."))
            if not self.idempotency_key:
                self.idempotency_key = "fiber-install:" + (self.acquisition_request or "")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{7,180}", self.idempotency_key or ""):
            frappe.throw(_("Closeout idempotency key must contain 8–180 safe characters."))

        previous = self.get_doc_before_save()
        immutable = (
            "acquisition_request", "assigned_technician", "ont_vendor", "ont_model",
            "ont_serial", "ont_mac", "olt_reference", "idempotency_key",
        )
        if previous and previous.docstatus == 1 and any(
            self.get(field) != previous.get(field) for field in immutable
        ):
            frappe.throw(_("Submitted installation identity and device references cannot be edited."))

        acquisition = frappe.get_doc("ISP Acquisition Request", self.acquisition_request)
        if acquisition.docstatus != 1:
            frappe.throw(_("The acquisition request must be submitted before installation closeout."))
        if acquisition.acquisition_status not in {"Payment Confirmed", "Installation Pending"}:
            frappe.throw(_("Installation is allowed only after the acquisition reaches Payment Confirmed or Installation Pending."))

        tech = self.assigned_technician
        if not frappe.db.get_value("User", tech, "enabled"):
            frappe.throw(_("Assigned technician must be an enabled user."))
        if "ISP Technician" not in frappe.get_roles(tech):
            frappe.throw(_("Assigned user must have the ISP Technician role."))
        gateway_actor = getattr(self, "_omisha_closeout_actor", None)
        if gateway_actor:
            if gateway_actor != tech:
                frappe.throw(_("Gateway closeout actor must be the assigned technician."))
        elif frappe.session.user != "Administrator" and frappe.session.user != tech:
            if "ISP Operations Manager" not in frappe.get_roles(frappe.session.user) and "System Manager" not in frappe.get_roles(frappe.session.user):
                frappe.throw(_("Only the assigned technician or an ISP operations manager can update this installation."))

        for field in ("ont_vendor", "ont_model", "ont_serial"):
            value = (self.get(field) or "").strip()
            if not value or len(value) > 128:
                frappe.throw(_("%s is required and must be 128 characters or fewer.") % self.meta.get_label(field))
        if self.ont_mac and not re.fullmatch(r"(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}", self.ont_mac.strip()):
            frappe.throw(_("ONT WAN MAC must use six colon-separated hexadecimal octets."))
        if self.optical_rx_dbm is not None and not -100 <= float(self.optical_rx_dbm) <= 20:
            frappe.throw(_("Optical receive power is outside the recordable range; confirm the meter and unit."))

        if previous and previous.docstatus == 1:
            frappe.throw(_("Submitted installation closeouts are immutable; create a new corrective job."))

    def before_submit(self):
        if self.installation_outcome == "Installed":
            if not (self.fiber_connected and self.ont_powered and self.optical_test_passed and self.wan_link_up):
                frappe.throw(_("Installed closeout requires fiber, ONT power, optical test, and WAN/link checks to pass."))
            if self.optical_rx_dbm is None:
                frappe.throw(_("Record the optical receive-power reading for an installed closeout."))
        elif self.installation_outcome in {"Failed", "Needs Review"}:
            if not self.failure_code:
                frappe.throw(_("A failure/review code is required when installation is not complete."))
            if not (self.technician_notes or "").strip():
                frappe.throw(_("Add a short technician note for failed or review closeout."))
        self.completed_at = frappe.utils.now_datetime()

    def on_submit(self):
        # Keep the outbox row in the same ERP transaction; never call NMS/ACS from this hook.
        event = frappe.get_doc({
            "doctype": "ISP Integration Event",
            "event_type": "fiber.installation." + self.installation_outcome.lower().replace(" ", "_"),
            "source_doctype": self.doctype,
            "source_name": self.name,
            "idempotency_key": "fiber-install:" + self.name + ":submitted",
            "payload_json": json.dumps({
                "schema": "isp.fiber-installation.v1",
                "installation_job": self.name,
                "acquisition_request": self.acquisition_request,
            }, sort_keys=True, separators=(",", ":")),
            "status": "Pending",
        })
        event.insert(ignore_permissions=True)
