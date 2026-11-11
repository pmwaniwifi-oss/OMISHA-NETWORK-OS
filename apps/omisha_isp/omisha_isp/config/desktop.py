from frappe import _


def get_data():
    return [{
        "module_name": "ISP Operations",
        "type": "module",
        "label": _("ISP Operations"),
        "color": "blue",
        "icon": "octicon octicon-radio-tower",
        "description": _("ISP service lifecycle and integration controls"),
    }]
