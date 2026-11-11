import json

import frappe
from frappe import _
from frappe.model.document import Document


class ISPIntegrationEvent(Document):
    def validate(self):
        if self.is_new() and self.status != "Pending":
            frappe.throw(_("New integration events must begin Pending."))
        if self.payload_json:
            try:
                payload = json.loads(self.payload_json)
            except (TypeError, json.JSONDecodeError):
                frappe.throw(_("Event payload must be valid JSON."))
            if not isinstance(payload, dict):
                frappe.throw(_("Event payload must be a JSON object."))

    def on_update(self):
        if self.status in ("Succeeded", "Dead Letter") and not self.completed_at:
            self.db_set("completed_at", frappe.utils.now_datetime(), update_modified=False)
