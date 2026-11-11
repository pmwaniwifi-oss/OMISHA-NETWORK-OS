"""Validate isolated, loopback-only NMS PostgreSQL without printing its config."""
import json
import sys

config = json.load(sys.stdin)
assert set(config['services']) == {'nms-postgres'}
db = config['services']['nms-postgres']
assert db['image'] == 'postgres:16-alpine'
assert db['environment']['POSTGRES_DB']
assert db['environment']['POSTGRES_USER']
assert db['environment']['POSTGRES_PASSWORD_FILE'] == '/run/secrets/nms_db_password'
assert not db['environment'].get('POSTGRES_PASSWORD')
assert len(db['ports']) == 1 and db['ports'][0]['host_ip'] == '127.0.0.1'
assert db['ports'][0]['published'] == '5432'
assert 'nms-postgres-data' in db['volumes'][0]['source']
assert config['networks']['nms-database']['driver'] == 'bridge'
print('NMS PostgreSQL is separate, persistent, secret-file based and loopback-only')
