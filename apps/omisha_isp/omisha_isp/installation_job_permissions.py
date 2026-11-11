import frappe


def _has_operations_override(user):
    return user == "Administrator" or {"System Manager", "ISP Operations Manager"}.intersection(
        frappe.get_roles(user)
    )


def get_permission_query_conditions(user=None):
    user = user or frappe.session.user
    if _has_operations_override(user):
        return ""
    if "ISP Technician" not in frappe.get_roles(user):
        return "1 = 0"
    return "tabISP Installation Job.assigned_technician = " + frappe.db.escape(user)


def has_installation_job_permission(doc, user=None, permission_type=None):
    user = user or frappe.session.user
    if _has_operations_override(user):
        return True
    if "ISP Technician" not in frappe.get_roles(user):
        return False
    return doc.assigned_technician == user
