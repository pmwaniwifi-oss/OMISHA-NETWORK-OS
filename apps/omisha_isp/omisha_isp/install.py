import frappe


def before_install():
    """Create app roles before importing DocTypes that declare those roles."""
    for role_name in ("ISP Operations Manager", "ISP Service Desk"):
        if not frappe.db.exists("Role", role_name):
            frappe.get_doc({
                "doctype": "Role",
                "role_name": role_name,
                "desk_access": 1,
                "is_custom": 1,
            }).insert(ignore_permissions=True)
