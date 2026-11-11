import hashlib
import json
import re

import frappe
from frappe import _


ALLOWED_CLOSEOUT_FIELDS = {
    "installation_outcome",
    "ont_vendor",
    "ont_model",
    "ont_serial",
    "ont_mac",
    "olt_reference",
    "fiber_connected",
    "ont_powered",
    "optical_test_passed",
    "optical_rx_dbm",
    "wan_link_up",
    "failure_code",
    "technician_notes",
}


@frappe.whitelist(methods=["POST"])
def submit_closeout(job_name=None, expected_technician=None, closeout=None):
    """Submit one assigned installation and atomically create its reference outbox event."""
    if "OMISHA Integration Gateway" not in frappe.get_roles(frappe.session.user):
        frappe.throw(_("Gateway role required."), frappe.PermissionError)

    if isinstance(closeout, str):
        try:
            closeout = json.loads(closeout)
        except (TypeError, json.JSONDecodeError):
            frappe.throw(_("Closeout payload must be valid JSON."), frappe.ValidationError)
    if not isinstance(closeout, dict) or set(closeout) != ALLOWED_CLOSEOUT_FIELDS:
        frappe.throw(_("Closeout payload fields are incomplete or unsupported."), frappe.ValidationError)
    if not isinstance(job_name, str) or not job_name or len(job_name) > 140 or not isinstance(expected_technician, str) or not expected_technician or len(expected_technician) > 140:
        frappe.throw(_("Installation job and technician are required."), frappe.ValidationError)

    text_limits = {
        "installation_outcome": 32, "ont_vendor": 128, "ont_model": 128,
        "ont_serial": 128, "ont_mac": 32, "olt_reference": 128,
        "failure_code": 80, "technician_notes": 2000,
    }
    for fieldname, limit in text_limits.items():
        value = closeout[fieldname]
        if not isinstance(value, str) or len(value) > limit:
            frappe.throw(_("Invalid closeout text field: %s") % fieldname, frappe.ValidationError)
    if closeout["installation_outcome"] not in {"Installed", "Failed", "Needs Review"}:
        frappe.throw(_("Invalid installation outcome."), frappe.ValidationError)
    for fieldname in ("fiber_connected", "ont_powered", "optical_test_passed", "wan_link_up"):
        if type(closeout[fieldname]) is not bool:
            frappe.throw(_("Closeout check fields must be true or false."), frappe.ValidationError)
    optical = closeout["optical_rx_dbm"]
    if optical is not None and (isinstance(optical, bool) or not isinstance(optical, (int, float)) or not -100 <= optical <= 20):
        frappe.throw(_("Invalid optical receive-power reading."), frappe.ValidationError)
    if closeout["ont_mac"] and not re.fullmatch(r"(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}", closeout["ont_mac"]):
        frappe.throw(_("Invalid ONT WAN MAC."), frappe.ValidationError)
    if closeout["installation_outcome"] != "Installed" and (
        closeout["failure_code"] not in {"No Signal", "Low Optical Power", "ONT Fault", "Port/Provisioning Issue", "Customer Premises Access", "Other"}
        or not closeout["technician_notes"].strip()
    ):
        frappe.throw(_("Failed or review closeout requires a valid failure code and note."), frappe.ValidationError)

    job = frappe.get_doc("ISP Installation Job", job_name)
    if job.assigned_technician != expected_technician:
        frappe.throw(_("This installation is not assigned to the authenticated technician."), frappe.PermissionError)
    if not frappe.db.get_value("User", expected_technician, "enabled"):
        frappe.throw(_("Assigned technician account is disabled."), frappe.PermissionError)
    if "ISP Technician" not in frappe.get_roles(expected_technician):
        frappe.throw(_("Assigned user does not have the ISP Technician role."), frappe.PermissionError)

    try:
        canonical = json.dumps(
            {"job": job.name, "technician": expected_technician, "closeout": closeout},
            sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False,
        )
    except (TypeError, ValueError):
        frappe.throw(_("Closeout payload is not canonical JSON."), frappe.ValidationError)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    if job.docstatus == 1:
        if job.closeout_request_digest == digest:
            return {"state": "already_submitted", "installation_job": job.name,
                    "installation_outcome": job.installation_outcome}
        return {"state": "conflict", "installation_job": job.name}
    if job.docstatus != 0:
        return {"state": "conflict", "installation_job": job.name}

    for fieldname, value in closeout.items():
        setattr(job, fieldname, value)
    job.closeout_submitted_by = expected_technician
    job.closeout_request_digest = digest
    # This context is transient; validate() still checks that the actor is the
    # assigned, enabled ISP Technician. It is never accepted from DocType input.
    job._omisha_closeout_actor = expected_technician
    job.flags.ignore_permissions = True
    job.submit()

    return {"state": "submitted", "installation_job": job.name,
            "installation_outcome": job.installation_outcome}
