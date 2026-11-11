app_name = "omisha_isp"
app_title = "OMISHA ISP Operations"
app_publisher = "OMISHA NETWORK OS"
app_description = "ISP service order and integration outbox foundations"
required_apps = ["erpnext"]
before_install = "omisha_isp.install.before_install"

permission_query_conditions = {
    "ISP Installation Job": "omisha_isp.installation_job_permissions.get_permission_query_conditions",
}

has_permission = {
    "ISP Installation Job": "omisha_isp.installation_job_permissions.has_installation_job_permission",
}
