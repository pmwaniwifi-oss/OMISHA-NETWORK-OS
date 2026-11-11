import json
import re

import frappe
from frappe import _
from frappe.model.document import Document


class ISPServiceOrder(Document):
    def validate(self):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{7,127}", self.idempotency_key or ""):
            frappe.throw(_("Idempotency Key must contain 8–128 safe characters."))
        if not frappe.db.exists("Customer", self.customer):
            frappe.throw(_("Customer does not exist on this client site."))
        if self.payload_json:
            try:
                payload = json.loads(self.payload_json)
            except (TypeError, json.JSONDecodeError):
                frappe.throw(_("Payload must be valid JSON."))
            if not isinstance(payload, dict) or len(self.payload_json.encode("utf-8")) > 16_384:
                frappe.throw(_("Payload must be a JSON object under 16 KiB."))
            allowed = {"access_type", "requested_speed_mbps", "service_address_ref"}
            if set(payload) - allowed:
                frappe.throw(_("Payload contains fields outside the approved provisioning schema."))
            speed = payload.get("requested_speed_mbps")
            if speed is not None and (type(speed) is not int or not 1 <= speed <= 100_000):
                frappe.throw(_("Requested speed must be an integer between 1 and 100000 Mbps."))
            access_type = payload.get("access_type")
            if access_type is not None and access_type not in {"fiber", "wireless", "docsis", "dsl", "ethernet"}:
                frappe.throw(_("Access type is not supported."))
            address = payload.get("service_address_ref")
            if address is not None:
                linked = frappe.db.exists("Dynamic Link", {
                    "parenttype": "Address", "parent": address,
                    "link_doctype": "Customer", "link_name": self.customer,
                })
                if not linked:
                    frappe.throw(_("Service address must be linked to the selected Customer."))

    def on_submit(self):
        # The event is inserted in the same Frappe transaction as this submission.
        # Do not make network calls inside document lifecycle hooks.
        event = frappe.get_doc({
            "doctype": "ISP Integration Event",
            "event_type": "service_order.submitted",
            "source_doctype": self.doctype,
            "source_name": self.name,
            "idempotency_key": "service-order:" + self.name + ":submitted",
            # The consumer resolves the order from its owning ERP site when needed.
            # Do not duplicate customer, plan or address data in an event queue.
            "payload_json": json.dumps({
                "schema": "isp.service-order.submitted.v1",
                "service_order": self.name,
            }, sort_keys=True, separators=(",", ":")),
            "status": "Pending",
        })
        event.insert(ignore_permissions=True)
