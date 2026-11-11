"""Validate the rendered pilot Compose model; do not print secret-bearing config."""
import json
import sys

config = json.load(sys.stdin)
services = config['services']
assert set(services) == {'configurator','backend','frontend','websocket','queue-short',
                         'queue-long','scheduler','db','redis-cache','redis-queue'}
for name, service in services.items():
    if name != 'frontend':
        assert not service.get('ports'), 'internal service publishes ports'
    else:
        assert len(service['ports']) == 1
        assert service['ports'][0]['host_ip'] == '127.0.0.1'
        assert service['ports'][0]['target'] == 8080
assert not services['db']['environment'].get('MYSQL_ROOT_PASSWORD'), 'inline password remains'
assert services['db']['environment']['MYSQL_ROOT_PASSWORD_FILE'] == '/run/secrets/db_password'
assert not services['db']['environment'].get('MARIADB_AUTO_UPGRADE'), 'automatic DB upgrade enabled'
assert services['backend']['image'] == 'frappe/erpnext:v16.54.0'
assert services['frontend']['environment']['FRAPPE_SITE_NAME_HEADER']
print('Frappe pilot Compose topology, private binding and secret-file configuration verified')
