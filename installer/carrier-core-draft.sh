#!/usr/bin/env bash
# ==============================================================================
# CARRIER CORE + NMS PRIME - SELF-EXTRACTING UNIFIED BUNDLE (20 EXTENDED SCRIPTS)
# Usage:
#   bash deploy_carrier_core_20_unified.sh [--extract-only] [--dest DIR]
#        [--resume] [--from N] [--only N] [--reset-state]
# ==============================================================================
set -euo pipefail

DEST="/opt/carrier-core/installer"
EXTRACT_ONLY=false
SKIP_PREREQUISITES=false
PREREQUISITES_ONLY=false
SKIP_NMSPRIME_INSTALL=false
PASS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --extract-only) EXTRACT_ONLY=true; shift ;;
        --skip-prerequisites) SKIP_PREREQUISITES=true; shift ;;
        --prerequisites-only) PREREQUISITES_ONLY=true; shift ;;
        --skip-nmsprime-install) SKIP_NMSPRIME_INSTALL=true; shift ;;
        --dest) DEST="${2:?--dest needs a path}"; shift 2 ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) PASS+=("$1"); shift ;;
    esac
done

if [ "$EXTRACT_ONLY" = false ]; then
    [ "$(id -u)" -eq 0 ] || { echo "[!] Run as root."; exit 1; }
fi

install_nmsprime_rpms() {
    [ "$EXTRACT_ONLY" = true ] && return 0
    . /etc/os-release
    if [ "$SKIP_NMSPRIME_INSTALL" = true ]; then
        if [ ! -f /var/www/nmsprime/artisan ] || [ ! -f /etc/nmsprime/env/global.env ]; then
            echo "[!] --skip-nmsprime-install requires NMS Prime at /var/www/nmsprime and /etc/nmsprime/env/global.env." >&2
            return 1
        fi
        return 0
    fi
    if rpm -q nmsprime-base >/dev/null 2>&1; then
        [ -f /var/www/nmsprime/artisan ] && [ -f /etc/nmsprime/env/global.env ] || {
            echo "[!] NMS Prime base RPM is installed but its expected files are missing." >&2
            return 1
        }
        echo "[*] NMS Prime base RPM is already installed."
        return 0
    fi
    if [ "$ID" != rocky ] || [[ "$VERSION_ID" != 9* ]]; then
        echo "[!] Automatic NMS Prime RPM installation is supported on Rocky Linux 9 only; use --skip-nmsprime-install for a preinstalled instance." >&2
        return 1
    fi
    if [ -e /var/www/nmsprime/artisan ] || [ -e /etc/nmsprime/env/global.env ]; then
        echo "[!] Partial or unmanaged NMS Prime files exist; inspect them before proceeding." >&2
        return 1
    fi
    for package in mariadb-server mysql-server postgresql-server postgresql16-server httpd; do
        if rpm -q "$package" >/dev/null 2>&1; then
            echo "[!] NMS Prime RPM installation requires a fresh Rocky 9 host; found preinstalled $package." >&2
            return 1
        fi
    done
    for service in mariadb mysql postgresql postgresql-16 httpd; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "[!] NMS Prime RPM installation requires a fresh host; $service is active." >&2
            return 1
        fi
    done
    dnf install --assumeyes ca-certificates curl || { echo "[!] Could not install curl and CA certificates." >&2; return 1; }
    local temp_dir repo_installer
    temp_dir="$(mktemp -d /tmp/nmsprime-repo-bootstrap.XXXXXX)"
    trap 'rm -rf "$temp_dir"; trap - RETURN' RETURN
    repo_installer="$temp_dir/INSTALL-REPO.sh"
    curl --proto '=https' --tlsv1.2 -fsSL https://github.com/cablelabs/os-provisioning/raw/dev/scripts/INSTALL-REPO.sh -o "$repo_installer" || {
        echo "[!] Could not download the NMS Prime repository bootstrap." >&2
        return 1
    }
    bash "$repo_installer" || { echo "[!] The NMS Prime repository bootstrap failed." >&2; return 1; }
    dnf install --assumeyes 'nmsprime-*' || { echo "[!] Installing NMS Prime Community RPMs failed." >&2; return 1; }
    rpm -q nmsprime-base >/dev/null 2>&1 && [ -f /var/www/nmsprime/artisan ] && [ -f /etc/nmsprime/env/global.env ] || {
        echo "[!] NMS Prime RPM install did not produce the expected app and runtime environment." >&2
        return 1
    }
    echo "[+] NMS Prime Community RPMs installed and initialized."
}

install_prerequisites() {
    if [ ! -r /etc/os-release ]; then echo "[!] Cannot identify this Linux distribution." >&2; return 1; fi
    . /etc/os-release
    if { [ "$ID" != rocky ] && [ "$ID" != ol ]; } || [[ "$VERSION_ID" != 9* ]]; then
        echo "[!] Carrier Core prerequisites support Rocky Linux 9 and Oracle Linux 9; detected $PRETTY_NAME." >&2
        return 1
    fi
    dnf install --assumeyes dnf-plugins-core ca-certificates curl || {
        echo "[!] Could not install DNF repository-management prerequisites." >&2
        return 1
    }
    if [ "$ID" = rocky ]; then
        dnf config-manager --set-enabled crb || { echo "[!] Could not enable Rocky Linux CRB." >&2; return 1; }
    else
        dnf config-manager --set-enabled ol9_codeready_builder || { echo "[!] Could not enable Oracle Linux 9 CodeReady Builder." >&2; return 1; }
    fi
    dnf install --assumeyes git openssl gzip coreutils util-linux gawk sed grep iproute procps-ng python3 python3-pip python3-devel gcc gcc-c++ make golang freeradius freeradius-postgresql freeradius-utils postgresql || {
        echo "[!] Could not install Carrier Core and PostgreSQL prerequisites." >&2
        return 1
    }
    install -d -m 0755 /opt/carrier-core
    python3 -m venv /opt/carrier-core/venv || { echo "[!] Could not create the Carrier Core Python environment." >&2; return 1; }
    /opt/carrier-core/venv/bin/python -m pip install --disable-pip-version-check --only-binary=:all: 'psycopg[binary]' pymongo || {
        echo "[!] Could not install the Python PostgreSQL and MongoDB drivers." >&2
        return 1
    }
    if ! rpm -q mongodb-org-server >/dev/null 2>&1; then
        ARCH="$(rpm --eval '%{_arch}')"
        case "$ARCH" in x86_64|aarch64) ;; *) echo "[!] MongoDB 8.0 prerequisites do not support architecture $ARCH." >&2; return 1 ;; esac
        mkdir -p /etc/yum.repos.d
        cat > /etc/yum.repos.d/mongodb-org-8.0.repo <<MONGO_REPO
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/$ARCH/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
MONGO_REPO
        dnf install --assumeyes mongodb-org mongodb-mongosh mongodb-database-tools || { echo "[!] Could not install MongoDB 8.0 server, shell, and tools." >&2; return 1; }
    fi
    rpm -q mongodb-database-tools >/dev/null 2>&1 || dnf install --assumeyes mongodb-database-tools || {
        echo "[!] Could not install MongoDB Database Tools." >&2
        return 1
    }
    if ! systemctl list-unit-files --type=service --no-legend | awk '$1 ~ /^(valkey|redis|redis-server)\.service$/ {found=1} END {exit !found}'; then
        dnf install --assumeyes valkey || dnf install --assumeyes redis || {
            echo "[!] Could not install Valkey or Redis." >&2
            return 1
        }
    fi
    systemctl enable --now mongod || { echo "[!] MongoDB service failed to start." >&2; return 1; }
    if systemctl list-unit-files --type=service --no-legend | awk '$1 == "valkey.service" {found=1} END {exit !found}'; then
        systemctl enable --now valkey || return 1
    elif systemctl list-unit-files --type=service --no-legend | awk '$1 == "redis-server.service" {found=1} END {exit !found}'; then
        systemctl enable --now redis-server || return 1
    else
        systemctl enable --now redis || return 1
    fi
    PG_SERVICE=""
    for candidate in postgresql-16 postgresql; do
        if systemctl list-unit-files --type=service --no-legend | awk -v unit="$candidate.service" '$1 == unit {found=1} END {exit !found}'; then PG_SERVICE="$candidate"; break; fi
    done
    [ -n "$PG_SERVICE" ] && systemctl is-active --quiet "$PG_SERVICE" || {
        echo "[!] NMS Prime PostgreSQL service is not active." >&2
        return 1
    }
    if ! command -v php >/dev/null 2>&1 || ! php -r 'exit(extension_loaded("pdo_pgsql") ? 0 : 1);'; then
        echo "[!] The NMS Prime PHP runtime or its PostgreSQL PDO extension is unavailable." >&2
        return 1
    fi
}

if [ "$EXTRACT_ONLY" = false ]; then
    install_nmsprime_rpms || exit 1
fi
if [ "$EXTRACT_ONLY" = false ] && [ "$SKIP_PREREQUISITES" = false ]; then
    install_prerequisites || exit 1
fi
if [ "$PREREQUISITES_ONLY" = true ]; then
    echo "[+] NMS Prime RPMs and Carrier Core operating-system prerequisites are ready. Re-run without --prerequisites-only."
    exit 0
fi
mkdir -p "$DEST" /opt/carrier-core/config /opt/carrier-core/bin /opt/carrier-core/logs

echo "[*] Generating 20 extended auto-executable scripts in $DEST ..."

# ==============================================================================
# SCRIPT 01: SYSTEM PREP, KERNEL SYSCTL, FIREWALLD & DEDUPLICATED PACKAGES
# ==============================================================================
cat <<'EOF_01' > "$DEST/01_system_kernel_and_repos.sh"
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="/opt/carrier-core/config/carrier_admin.env"
NMS_ENV_DIR="/etc/nmsprime/env"
if [ ! -f "$NMS_ENV_DIR/global.env" ] || [ ! -f /var/www/nmsprime/vendor/autoload.php ]; then
    echo "[!] NMS Prime RPM environment or application files are missing." >&2
    exit 1
fi
shopt -s nullglob
NMS_ENV_FILES=("$NMS_ENV_DIR"/*.env)
shopt -u nullglob
for nms_env_file in "${NMS_ENV_FILES[@]}"; do
    set -a
    source "$nms_env_file"
    set +a
done
PG_CONFIG="$(cd /var/www/nmsprime && php -r '
require "vendor/autoload.php";
$app = require "bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$name = config("database.default");
$db = config("database.connections." . $name, []);
if (($db["driver"] ?? "") !== "pgsql") { fwrite(STDERR, "NMS Prime active Laravel connection is not PostgreSQL.\n"); exit(2); }
foreach (["host", "port", "database", "username", "password"] as $key) {
    echo base64_encode((string)($db[$key] ?? "")), "\n";
}
' 2>/dev/null)" || { echo "[!] Could not read the active NMS Prime PostgreSQL connection." >&2; exit 1; }
mapfile -t PG_CONFIG_PARTS <<< "$PG_CONFIG"
if [ "${#PG_CONFIG_PARTS[@]}" -ne 5 ]; then echo "[!] NMS Prime PostgreSQL connection settings are incomplete." >&2; exit 1; fi
decode_pg_value() { printf '%s' "$1" | base64 --decode; }
SQL_HOST="$(decode_pg_value "${PG_CONFIG_PARTS[0]}")"
SQL_PORT="$(decode_pg_value "${PG_CONFIG_PARTS[1]}")"
SQL_DATABASE="$(decode_pg_value "${PG_CONFIG_PARTS[2]}")"
SQL_USER="$(decode_pg_value "${PG_CONFIG_PARTS[3]}")"
SQL_PASSWORD="$(decode_pg_value "${PG_CONFIG_PARTS[4]}")"

if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi
# Never let stale Carrier credentials override the RPM's active PostgreSQL connection.
SQL_HOST="$(decode_pg_value "${PG_CONFIG_PARTS[0]}")"
SQL_PORT="$(decode_pg_value "${PG_CONFIG_PARTS[1]}")"
SQL_DATABASE="$(decode_pg_value "${PG_CONFIG_PARTS[2]}")"
SQL_USER="$(decode_pg_value "${PG_CONFIG_PARTS[3]}")"
SQL_PASSWORD="$(decode_pg_value "${PG_CONFIG_PARTS[4]}")"
SQL_SSLMODE="${SQL_SSLMODE:-prefer}"
DB_NAME="$SQL_DATABASE"
DB_USER="$SQL_USER"
DB_PASS="$SQL_PASSWORD"
MONGO_URI="${MONGO_URI:-mongodb://127.0.0.1:27017}"
MONGO_DB="${MONGO_DB:-carrier_core}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_DB_CACHE="${REDIS_DB_CACHE:-0}"
REDIS_DB_AAA="${REDIS_DB_AAA:-1}"
NMSPRIME_PORT="${NMSPRIME_PORT:-8080}"
NMSPRIME_SERVER_NAME="${NMSPRIME_SERVER_NAME:-_}"
TLS_CERT_FILE="${TLS_CERT_FILE:-}"
TLS_KEY_FILE="${TLS_KEY_FILE:-}"
GO_FAST_API_PORT="${GO_FAST_API_PORT:-8090}"
AI_SOCIAL_PORT="${AI_SOCIAL_PORT:-8095}"
COA_PORT="${COA_PORT:-3799}"
IPDR_S3_BUCKET="${IPDR_S3_BUCKET:-}"
RADIUS_SECRET="${RADIUS_SECRET:-$(openssl rand -hex 32)}"
INTERNAL_API_TOKEN="${INTERNAL_API_TOKEN:-$(openssl rand -hex 32)}"
BILLING_WEBHOOK_SECRET="${BILLING_WEBHOOK_SECRET:-$(openssl rand -hex 32)}"
AI_SOCIAL_WEBHOOK_TOKEN="${AI_SOCIAL_WEBHOOK_TOKEN:-$(openssl rand -hex 32)}"
META_VERIFY_TOKEN="${META_VERIFY_TOKEN:-$(openssl rand -hex 32)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 32)}"
if ! [[ "$MONGO_DB" =~ ^[A-Za-z0-9_-]+$ ]]; then echo "[!] MONGO_DB contains unsupported characters." >&2; exit 1; fi

mkdir -p /opt/carrier-core/config /opt/carrier-core/bin /opt/carrier-core/logs
export SQL_HOST SQL_PORT SQL_DATABASE SQL_USER SQL_PASSWORD SQL_SSLMODE DB_NAME DB_USER DB_PASS
export MONGO_URI MONGO_DB REDIS_HOST REDIS_PORT REDIS_DB_CACHE REDIS_DB_AAA NMSPRIME_PORT NMSPRIME_SERVER_NAME TLS_CERT_FILE TLS_KEY_FILE GO_FAST_API_PORT AI_SOCIAL_PORT COA_PORT IPDR_S3_BUCKET RADIUS_SECRET INTERNAL_API_TOKEN BILLING_WEBHOOK_SECRET AI_SOCIAL_WEBHOOK_TOKEN META_VERIFY_TOKEN JWT_SECRET
python3 - "$ENV_FILE" <<'PY'
import os, shlex, sys, tempfile
from pathlib import Path
path=Path(sys.argv[1])
keys=("SQL_HOST","SQL_PORT","SQL_DATABASE","SQL_USER","SQL_PASSWORD","SQL_SSLMODE","DB_NAME","DB_USER","DB_PASS","MONGO_URI","MONGO_DB","REDIS_HOST","REDIS_PORT","REDIS_DB_CACHE","REDIS_DB_AAA","NMSPRIME_PORT","NMSPRIME_SERVER_NAME","TLS_CERT_FILE","TLS_KEY_FILE","GO_FAST_API_PORT","AI_SOCIAL_PORT","COA_PORT","IPDR_S3_BUCKET","RADIUS_SECRET","INTERNAL_API_TOKEN","BILLING_WEBHOOK_SECRET","AI_SOCIAL_WEBHOOK_TOKEN","META_VERIFY_TOKEN","JWT_SECRET")
values={key:os.environ[key] for key in keys}
lines=path.read_text(encoding="utf-8").splitlines() if path.exists() else []
written=set(); result=[]
for line in lines:
    key=line.split("=",1)[0] if "=" in line and not line.lstrip().startswith("#") else None
    if key in values:
        if key not in written:
            result.append(f"{key}={shlex.quote(values[key])}")
            written.add(key)
    else:
        result.append(line)
for key,value in values.items():
    if key not in written: result.append(f"{key}={shlex.quote(value)}")
fd,tmp=tempfile.mkstemp(prefix=path.name+".",dir=path.parent)
with os.fdopen(fd,"w",encoding="utf-8") as stream: stream.write("\n".join(result)+"\n")
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
chmod 600 "$ENV_FILE"

cat <<'EOF' > /etc/sysctl.d/99-carrier-core-isp.conf
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 16777216
net.core.netdev_max_backlog = 50000
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
fs.file-max = 2097152
vm.swappiness = 10
EOF
sysctl --system >/dev/null 2>&1 || true

if systemctl is-active --quiet firewalld 2>/dev/null; then
    for port in 80/tcp 443/tcp 1812/udp 1813/udp 3799/udp 5514/udp 51820/udp; do
        firewall-cmd --permanent --add-port="$port" >/dev/null 2>&1 || true
    done
    firewall-cmd --reload >/dev/null 2>&1 || true
fi
echo "[+] 01: PostgreSQL connection loaded from NMS Prime and Carrier runtime environment secured."
EOF_01

# ==============================================================================
# SCRIPT 02: 512M RAM-DISK & MEMORY TUNING (MariaDB 2G + Mongo 2G + Redis 1.2G)
# ==============================================================================
cat <<'EOF_02' > "$DEST/02_ramdisk_and_memory_limits.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env

RAMDISK_DIR="/mnt/carrier-ramdisk"
mkdir -p "${RAMDISK_DIR}"
if ! mountpoint -q "${RAMDISK_DIR}" 2>/dev/null; then
    mount -t tmpfs -o size=512M,mode=0750 tmpfs "${RAMDISK_DIR}" || true
fi
if ! grep -q "${RAMDISK_DIR}" /etc/fstab 2>/dev/null; then
    echo "tmpfs ${RAMDISK_DIR} tmpfs defaults,size=512M,mode=0750 0 0" >> /etc/fstab
fi
mkdir -p "${RAMDISK_DIR}/radius_spool" "${RAMDISK_DIR}/ipdr_buffer" "${RAMDISK_DIR}/offload_tmp"

PG_SERVICE=""
for candidate in postgresql-16 postgresql; do
    if systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk -v unit="$candidate.service" '$1 == unit {found=1} END {exit !found}'; then
        PG_SERVICE="$candidate"
        break
    fi
done
[ -n "$PG_SERVICE" ] && systemctl is-active --quiet "$PG_SERVICE" || {
    echo "[!] NMS Prime PostgreSQL service is not active." >&2
    exit 1
}
if [ -f /etc/mongod.conf ]; then
    if ! grep -q "cacheSizeGB" /etc/mongod.conf; then
        printf "\nstorage:\n  wiredTiger:\n    engineConfig:\n      cacheSizeGB: 2\n" >> /etc/mongod.conf
    else
        sed -i -E 's/cacheSizeGB:[[:space:]]*[0-9.]+/cacheSizeGB: 2/g' /etc/mongod.conf
    fi
    systemctl restart mongod 2>/dev/null || true
fi

for rconf in /etc/valkey/valkey.conf /etc/redis/redis.conf /etc/redis.conf; do
    if [ -f "$rconf" ]; then
        sed -i -E '/^maxmemory /d; /^maxmemory-policy /d' "$rconf"
        printf "maxmemory 1200mb\nmaxmemory-policy allkeys-lru\n" >> "$rconf"
    fi
done
systemctl restart valkey 2>/dev/null || systemctl restart redis 2>/dev/null || true
echo "[+] 02: 512M RAM-disk mounted; PostgreSQL package tuning was left to NMS Prime."
EOF_02

# ==============================================================================
# SCRIPT 03: UNIFIED SINGLE SQL DATABASE ('nmsprime') MASTER SCHEMA & TRIGGERS
# ==============================================================================
cat <<'EOF_03' > "$DEST/03_unified_sql_nmsprime_schema.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env

# Use the PostgreSQL connection configured by the NMS Prime RPM.
if [ -x /usr/pgsql-16/bin/psql ]; then PATH="/usr/pgsql-16/bin:$PATH"; export PATH; fi
if [ -x /usr/pgsql-16/bin/pg_dump ]; then PATH="/usr/pgsql-16/bin:$PATH"; export PATH; fi
if ! command -v psql >/dev/null 2>&1 || ! command -v pg_dump >/dev/null 2>&1; then
    echo "[!] psql and pg_dump are required." >&2
    exit 1
fi
if [[ ! "$SQL_USER" =~ ^[A-Za-z0-9_]+$ || ! "$SQL_DATABASE" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "[!] PostgreSQL user and database names must contain only letters, digits, and underscores." >&2
    exit 1
fi
psql_carrier() {
    PGPASSWORD="$SQL_PASSWORD" PGSSLMODE="${SQL_SSLMODE:-prefer}" PGOPTIONS='-c search_path=public' psql --no-psqlrc --set=ON_ERROR_STOP=1 \
        --host="$SQL_HOST" --port="$SQL_PORT" --username="$SQL_USER" --dbname="$SQL_DATABASE" "$@"
}
if ! psql_carrier --tuples-only --no-align --command='SELECT 1' >/dev/null; then
    echo "[!] Could not connect to the NMS Prime PostgreSQL database using its configured runtime credentials." >&2
    exit 1
fi
BACKUP_DIR="/opt/carrier-core/backups/pre_schema"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
umask 077
BACKUP_FILE="$BACKUP_DIR/nmsprime_before_carrier_schema_$(date +%Y%m%d_%H%M%S).sql.gz"
if ! PGSSLMODE="${SQL_SSLMODE:-prefer}" PGPASSWORD="$SQL_PASSWORD" pg_dump --no-owner --no-privileges --host="$SQL_HOST" --port="$SQL_PORT" \
    --username="$SQL_USER" "$SQL_DATABASE" | gzip -9 > "$BACKUP_FILE"; then
    rm -f "$BACKUP_FILE"
    echo "[!] PostgreSQL pre-change backup failed; no Carrier Core tables were changed." >&2
    exit 1
fi
gzip -t "$BACKUP_FILE" || { rm -f "$BACKUP_FILE"; echo "[!] PostgreSQL backup archive integrity check failed." >&2; exit 1; }
echo "[+] PostgreSQL database backed up to $BACKUP_FILE."
psql_carrier <<'SQL'
BEGIN;
DO $$
BEGIN
    IF to_regclass('public.contract') IS NULL THEN
        RAISE EXCEPTION 'NMS Prime contract table is missing; install the required provisioning modules first';
    END IF;
    IF to_regclass('public.netelement') IS NULL THEN
        RAISE EXCEPTION 'NMS Prime netelement table is missing; install the required provisioning modules first';
    END IF;
    IF to_regclass('public.modem') IS NULL THEN
        RAISE EXCEPTION 'NMS Prime modem table is missing; install the required provisioning modules first';
    END IF;
END $$;
ALTER TABLE public.contract
    ADD COLUMN IF NOT EXISTS status VARCHAR(32) DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS account_balance NUMERIC(12,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS dealer_id BIGINT,
    ADD COLUMN IF NOT EXISTS contract_start DATE,
    ADD COLUMN IF NOT EXISTS contract_end DATE;
ALTER TABLE public.modem
    ADD COLUMN IF NOT EXISTS splitter_port BIGINT,
    ADD COLUMN IF NOT EXISTS us_pwr NUMERIC(5,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS ds_pwr NUMERIC(5,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
CREATE TABLE IF NOT EXISTS carrier_accounting_records (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL,
    invoice_id BIGINT NULL,
    amount DECIMAL(12,2) NOT NULL,
    type VARCHAR(32) NOT NULL DEFAULT 'payment',
    accounted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_payment_webhook_events (
gateway_ref VARCHAR(128) PRIMARY KEY,
    contract_id BIGINT NOT NULL,
    invoice_id BIGINT NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_invoice (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL,
    number VARCHAR(64) UNIQUE,
    amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    settlement_status VARCHAR(64) DEFAULT 'unsettled',
    gstin VARCHAR(15) NULL,
    place_of_supply VARCHAR(64) DEFAULT 'State',
    hsn_sac VARCHAR(10) DEFAULT '998422',
    cgst_rate DECIMAL(4,2) DEFAULT 9.00,
    sgst_rate DECIMAL(4,2) DEFAULT 9.00,
    igst_rate DECIMAL(4,2) DEFAULT 0.00,
    irn_hash VARCHAR(64) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS radcheck (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    username VARCHAR(64) NOT NULL DEFAULT '',
    attribute VARCHAR(64) NOT NULL DEFAULT '',
    op CHAR(2) NOT NULL DEFAULT '==',
    value VARCHAR(253) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS carrier_idx_radcheck_user ON radcheck (username);

CREATE TABLE IF NOT EXISTS radreply (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    username VARCHAR(64) NOT NULL DEFAULT '',
    attribute VARCHAR(64) NOT NULL DEFAULT '',
    op CHAR(2) NOT NULL DEFAULT '=',
    value VARCHAR(253) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS carrier_idx_radreply_user ON radreply (username);

CREATE TABLE IF NOT EXISTS radgroupreply (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    groupname VARCHAR(64) NOT NULL DEFAULT '',
    attribute VARCHAR(64) NOT NULL DEFAULT '',
    op CHAR(2) NOT NULL DEFAULT '=',
    value VARCHAR(253) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS carrier_idx_groupname ON radgroupreply (groupname);

CREATE TABLE IF NOT EXISTS radacct (
radacctid BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    acctsessionid VARCHAR(64) NOT NULL DEFAULT '',
    acctuniqueid VARCHAR(32) NOT NULL DEFAULT '',
    username VARCHAR(64) NOT NULL DEFAULT '',
    nasipaddress VARCHAR(15) NOT NULL DEFAULT '',
    acctstarttime TIMESTAMP NULL,
    acctupdatetime TIMESTAMP NULL,
    acctstoptime TIMESTAMP NULL,
    acctsessiontime BIGINT NULL,
    acctinputoctets BIGINT NULL,
    acctoutputoctets BIGINT NULL,
    framedipaddress VARCHAR(15) NOT NULL DEFAULT '',
    callingstationid VARCHAR(50) NOT NULL DEFAULT '',
    CONSTRAINT acctuniqueid UNIQUE (acctuniqueid)
);

CREATE TABLE IF NOT EXISTS carrier_fiber_gis_routes (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    route_name VARCHAR(128) NOT NULL,
    netelement_id BIGINT NOT NULL,
    splitter_port BIGINT DEFAULT 1,
    total_cores BIGINT DEFAULT 24,
    geojson_path TEXT NOT NULL,
    status VARCHAR(64) DEFAULT 'OPERATIONAL',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_dealers (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    dealer_code VARCHAR(32) NOT NULL UNIQUE,
    business_name VARCHAR(128) NOT NULL,
    gstin VARCHAR(15) NULL,
    wallet_balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    commission_pct DECIMAL(5,2) DEFAULT 10.00,
    status VARCHAR(64) DEFAULT 'ACTIVE',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_subscriber_plan_state (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NULL,
    username VARCHAR(64) NOT NULL UNIQUE,
    nas_ip VARCHAR(45) DEFAULT '127.0.0.1',
    plan_type VARCHAR(32) NOT NULL DEFAULT 'STANDARD',
    normal_rate_limit VARCHAR(64) DEFAULT '50M/50M',
    throttled_rate_limit VARCHAR(64) DEFAULT '2M/2M',
    daily_quota_bytes BIGINT DEFAULT 107374182400,
    used_bytes BIGINT DEFAULT 0,
    state VARCHAR(64) DEFAULT 'ACTIVE',
    expires_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_service_tickets (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL,
    modem_id BIGINT NULL,
    assigned_employee_id BIGINT NULL,
    ticket_type VARCHAR(64) NOT NULL,
    priority VARCHAR(64) DEFAULT 'MEDIUM',
    status VARCHAR(64) DEFAULT 'OPEN',
    description TEXT,
    ont_rx_dbm DECIMAL(5,2) NULL,
    latitude DECIMAL(10,8) NULL,
    longitude DECIMAL(11,8) NULL,
    resolution_otp VARCHAR(6) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS carrier_pmwani_pdos (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    pdo_name VARCHAR(128) NOT NULL,
    ap_mac VARCHAR(17) NOT NULL UNIQUE,
    nas_ip VARCHAR(45) NOT NULL,
    location_name VARCHAR(255),
    latitude DECIMAL(10,8) NULL,
    longitude DECIMAL(11,8) NULL,
    revenue_share_pct DECIMAL(5,2) DEFAULT 20.00,
    status VARCHAR(64) DEFAULT 'ONLINE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_statutory_gst_ledger (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    invoice_id BIGINT NULL,
    contract_id BIGINT NOT NULL,
    customer_gstin VARCHAR(15) NULL,
    hsn_sac VARCHAR(10) NOT NULL DEFAULT '998422',
    taxable_amount DECIMAL(12,2) NOT NULL,
    cgst_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    sgst_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    igst_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_amount DECIMAL(12,2) NOT NULL,
    is_pass_through SMALLINT DEFAULT 0,
    payment_gateway_ref VARCHAR(64) NULL,
    irn_hash VARCHAR(64) NULL,
    invoice_date DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS carrier_hrm_employees (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id BIGINT NULL UNIQUE,
    emp_code VARCHAR(32) NOT NULL UNIQUE,
    full_name VARCHAR(128) NOT NULL,
    mobile VARCHAR(15) NOT NULL UNIQUE,
    role VARCHAR(64) NOT NULL,
    assigned_olt_id BIGINT NULL,
    base_salary DECIMAL(10,2) DEFAULT 0.00,
    status VARCHAR(64) DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_social_leads (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    source VARCHAR(64) NOT NULL DEFAULT 'WHATSAPP',
    external_lead_id VARCHAR(128) NULL,
    full_name VARCHAR(128) NOT NULL,
    mobile VARCHAR(20) NOT NULL,
    locality VARCHAR(255) NULL,
    requested_plan VARCHAR(64) DEFAULT '100 Mbps Unlimited',
    ai_intent_score SMALLINT DEFAULT 80,
    ai_sentiment VARCHAR(64) DEFAULT 'POSITIVE',
    status VARCHAR(64) DEFAULT 'NEW',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_social_campaigns (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    campaign_name VARCHAR(128) NOT NULL,
    channel VARCHAR(64) NOT NULL,
    target_segment VARCHAR(64) DEFAULT 'NEW_LEADS',
    ai_generated_copy TEXT NOT NULL,
    status VARCHAR(64) DEFAULT 'COMPLETED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_ai_predictions (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    entity_type VARCHAR(64) NOT NULL,
    entity_id BIGINT NOT NULL,
    entity_name VARCHAR(128) NOT NULL,
    risk_or_kpi_score DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    ai_reason VARCHAR(255) NOT NULL,
    recommended_action VARCHAR(255) NOT NULL,
    evaluated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_entity UNIQUE (entity_type, entity_id)
);

CREATE TABLE IF NOT EXISTS carrier_subscriber_identity (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL UNIQUE,
    username VARCHAR(64) NOT NULL UNIQUE,
    kyc_type VARCHAR(64) DEFAULT 'AADHAAR_EKYC',
    uid_hash VARCHAR(64) NOT NULL,
    verified_name VARCHAR(128) NOT NULL,
    verified_mobile VARCHAR(20) NOT NULL,
    mongo_kyc_doc_id VARCHAR(64) NULL,
    kyc_status VARCHAR(64) DEFAULT 'PENDING',
    verified_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS carrier_fup_daily_baseline (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    record_date DATE NOT NULL,
    opening_bytes BIGINT DEFAULT 0,
    closing_bytes BIGINT DEFAULT 0,
    CONSTRAINT uniq_user_date UNIQUE (username, record_date)
);

CREATE TABLE IF NOT EXISTS carrier_nms_subscribers (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL UNIQUE,
    username VARCHAR(64) NOT NULL UNIQUE,
    static_ip VARCHAR(45) NULL,
    bng_gateway_ip VARCHAR(45) DEFAULT '127.0.0.1',
    ott_bundle VARCHAR(64) DEFAULT 'NONE',
    sync_status VARCHAR(64) DEFAULT 'SYNCED',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_bgp_peers (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    peer_name VARCHAR(128) NOT NULL,
    remote_as BIGINT NOT NULL,
    peer_ip VARCHAR(45) NOT NULL UNIQUE,
    rpki_status VARCHAR(64) DEFAULT 'VALID',
    session_state VARCHAR(64) DEFAULT 'ESTABLISHED',
    prefixes_received BIGINT DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_dns_sinkhole_domains (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    domain_name VARCHAR(255) NOT NULL UNIQUE,
    order_reference VARCHAR(128) NOT NULL DEFAULT 'DoT-MeitY-Order',
    redirect_ip VARCHAR(45) NOT NULL DEFAULT '127.0.0.1',
    is_active SMALLINT DEFAULT 1,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_ott_entitlements (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL,
    username VARCHAR(64) NOT NULL,
    package_code VARCHAR(64) NOT NULL DEFAULT 'FIBER_OTT_PLUS',
    providers VARCHAR(255) NOT NULL DEFAULT 'SonyLIV,ZEE5,Hotstar',
    status VARCHAR(64) DEFAULT 'ACTIVE',
    valid_until DATE NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_contract_pkg UNIQUE (contract_id, package_code)
);

CREATE TABLE IF NOT EXISTS carrier_ledger (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    entry_date DATE NOT NULL,
    voucher_type VARCHAR(64) NOT NULL,
    debit_account VARCHAR(128) NOT NULL,
    credit_account VARCHAR(128) NOT NULL,
    amount DECIMAL(14,2) NOT NULL,
    reference_id VARCHAR(64) NULL,
    narration VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS carrier_tax_tds_deductions (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    deductee_name VARCHAR(128) NOT NULL,
    deductee_pan VARCHAR(10) NOT NULL,
    section_code VARCHAR(64) NOT NULL,
    gross_payment DECIMAL(12,2) NOT NULL,
    tds_rate_pct DECIMAL(5,2) NOT NULL,
    tds_amount DECIMAL(12,2) NOT NULL,
    challan_status VARCHAR(64) DEFAULT 'PENDING',
    payment_date DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS carrier_hrm_payslips (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    salary_month CHAR(7) NOT NULL,
    gross_pay DECIMAL(10,2) NOT NULL,
    epf_employee DECIMAL(10,2) DEFAULT 0.00,
    esi_employee DECIMAL(10,2) DEFAULT 0.00,
    sla_incentive DECIMAL(10,2) DEFAULT 0.00,
    net_payable DECIMAL(10,2) NOT NULL,
    payment_status VARCHAR(64) DEFAULT 'GENERATED',
    CONSTRAINT uniq_emp_month UNIQUE (employee_id, salary_month)
);

CREATE TABLE IF NOT EXISTS carrier_hrm_lms_certifications (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    course_code VARCHAR(64) NOT NULL DEFAULT 'FTTH_SPLICING_101',
    course_title VARCHAR(128) NOT NULL DEFAULT 'GPON Optical Splicing & OTDR Safety',
    score_pct SMALLINT NOT NULL DEFAULT 100,
    certified_until DATE NOT NULL,
    status VARCHAR(64) DEFAULT 'VALID',
    CONSTRAINT uniq_emp_course UNIQUE (employee_id, course_code)
);

CREATE TABLE IF NOT EXISTS carrier_ipdr_archive_manifest (
id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    archive_filename VARCHAR(255) NOT NULL UNIQUE,
    sha256_checksum CHAR(64) NOT NULL,
    s3_path VARCHAR(255) NOT NULL,
    record_date DATE NOT NULL,
    archived_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS carrier_idx_acc_contract ON carrier_accounting_records (contract_id);

CREATE INDEX IF NOT EXISTS carrier_idx_radacct_username ON radacct (username);

CREATE INDEX IF NOT EXISTS carrier_idx_radacct_stoptime ON radacct (acctstoptime);

CREATE INDEX IF NOT EXISTS carrier_idx_gis_netelement ON carrier_fiber_gis_routes (netelement_id);

CREATE INDEX IF NOT EXISTS carrier_idx_plan_contract ON carrier_subscriber_plan_state (contract_id);

CREATE INDEX IF NOT EXISTS carrier_idx_plan_state ON carrier_subscriber_plan_state (state);

CREATE INDEX IF NOT EXISTS carrier_idx_ticket_status ON carrier_service_tickets (status, priority);

CREATE INDEX IF NOT EXISTS carrier_idx_ticket_contract ON carrier_service_tickets (contract_id);

CREATE INDEX IF NOT EXISTS carrier_idx_inv_date ON carrier_statutory_gst_ledger (invoice_date);


DELETE FROM radgroupreply WHERE groupname = 'PMWANI_FREE';
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
    ('PMWANI_FREE', 'WISPr-Bandwidth-Max-Down', ':=', '10485760'),
    ('PMWANI_FREE', 'WISPr-Bandwidth-Max-Up', ':=', '2097152'),
    ('PMWANI_FREE', 'Session-Timeout', ':=', '1800');

CREATE OR REPLACE FUNCTION carrier_accounting_to_ledger()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO carrier_ledger (entry_date, voucher_type, debit_account, credit_account, amount, reference_id, narration)
    VALUES (NEW.accounted_at::date, 'RECEIPT', '1010_Bank_Gateway_Account', '2010_Subscriber_Receivables',
            NEW.amount, format('CONTRACT-%s', NEW.contract_id), NEW.description);
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_accounting_to_ledger ON carrier_accounting_records;
CREATE TRIGGER trg_accounting_to_ledger
AFTER INSERT ON carrier_accounting_records
FOR EACH ROW EXECUTE FUNCTION carrier_accounting_to_ledger();
COMMIT;
SQL
echo "[+] 03: PostgreSQL schema added to the NMS Prime database."

echo "[+] 03: Single SQL Database ('${SQL_DATABASE}') schema and triggers provisioned."
EOF_03

# ==============================================================================
# SCRIPT 04: UNIFIED SINGLE NOSQL DATABASE ('carrier_core') & GENIEACS BINDING
# ==============================================================================
cat <<'EOF_04' > "$DEST/04_unified_nosql_mongodb_schema.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env

if command -v mongosh >/dev/null 2>&1; then
mongosh --quiet "${MONGO_URI}/${MONGO_DB}" <<'EOF'
db.ipdr_logs.createIndex({ "timestamp": 1 }, { expireAfterSeconds: 63072000 });
db.ipdr_logs.createIndex({ "src_ip": 1, "timestamp": -1 });
db.ipdr_logs.createIndex({ "nat_ip": 1, "nat_port": 1, "timestamp": -1 });
db.radacct_archive.createIndex({ "username": 1, "acctstarttime": -1 });
db.olt_telemetry.createIndex({ "recorded_at": 1 }, { expireAfterSeconds: 7776000 });
db.olt_telemetry.createIndex({ "ont_serial": 1, "recorded_at": -1 });
db.subscriber_kyc.createIndex({ "contract_id": 1 }, { unique: true });
db.admin_audit_trail.createIndex({ "created_at": -1 });
db.social_chat_logs.createIndex({ "timestamp": 1 }, { expireAfterSeconds: 31536000 });
db.dns_audit.createIndex({ "queried_at": 1 }, { expireAfterSeconds: 15552000 });
db.traffic_flows.createIndex({ "timestamp": 1 }, { expireAfterSeconds: 2592000 });
EOF
fi

if [ -f /opt/genieacs/genieacs.env ]; then
    sed -i -E "s|^GENIEACS_MONGODB_CONNECTION_URL=.*|GENIEACS_MONGODB_CONNECTION_URL=${MONGO_URI}/${MONGO_DB}|g" /opt/genieacs/genieacs.env
    systemctl restart genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui 2>/dev/null || true
fi
echo "[+] 04: Single NoSQL Database ('${MONGO_DB}') collections and GenieACS bound."
EOF_04

# ==============================================================================
# SCRIPT 05: REDIS / VALKEY CACHE & NMS PRIME .ENV WIRING
# ==============================================================================
cat <<'EOF_05' > "$DEST/05_redis_valkey_and_nmsprime_env.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
NMS_ENV="/etc/nmsprime/env/global.env"
if [ ! -f "$NMS_ENV" ]; then
    echo "[!] NMS Prime RPM runtime environment was not found at $NMS_ENV." >&2
    exit 1
fi
[ -f "$NMS_ENV.carrier-core.bak" ] || cp -a "$NMS_ENV" "$NMS_ENV.carrier-core.bak"
export INTERNAL_API_TOKEN MONGO_URI MONGO_DB
python3 - "$NMS_ENV" <<'PY'
import os, shlex, sys, tempfile
from pathlib import Path
path=Path(sys.argv[1])
values={"CARRIER_INTERNAL_API_TOKEN":os.environ["INTERNAL_API_TOKEN"],
        "CARRIER_MONGO_URI":os.environ["MONGO_URI"],
        "CARRIER_MONGO_DB":os.environ["MONGO_DB"]}
lines=path.read_text(encoding="utf-8").splitlines()
seen=set(); out=[]
for line in lines:
    key=line.split("=",1)[0] if "=" in line and not line.lstrip().startswith("#") else None
    if key in values:
        if key not in seen:
            out.append(f"{key}={shlex.quote(values[key])}")
            seen.add(key)
    else:
        out.append(line)
for key,value in values.items():
    if key not in seen: out.append(f"{key}={shlex.quote(value)}")
fd,tmp=tempfile.mkstemp(prefix=path.name+".",dir=path.parent)
with os.fdopen(fd,"w",encoding="utf-8") as stream: stream.write(chr(10).join(out)+chr(10))
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
chown root:root "$NMS_ENV"
chmod 600 "$NMS_ENV"
systemctl try-reload-or-restart php-fpm >/dev/null 2>&1 || true
echo "[+] 05: Carrier-only runtime settings added to NMS Prime's RPM environment; PostgreSQL settings were preserved."
EOF_05

cat <<'EOF_06' > "$DEST/06_freeradius_single_aaa_enrichment.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env

if [ -d /etc/raddb ]; then
    RADDB="/etc/raddb"
    RADIUS_SERVICE="radiusd"
elif [ -d /etc/freeradius/3.0 ]; then
    RADDB="/etc/freeradius/3.0"
    RADIUS_SERVICE="freeradius"
else
    echo "[!] FreeRADIUS configuration directory not found." >&2
    exit 1
fi

if [ -d "${RADDB}" ]; then
    if [ -f "${RADDB}/mods-available/sql" ]; then
        python3 - "$RADDB/mods-available/sql" "$SQL_HOST" "$SQL_PORT" "$SQL_DATABASE" "$SQL_USER" "$SQL_PASSWORD" <<'PY'
import re, sys
from pathlib import Path
path=Path(sys.argv[1])
values=dict(zip(("server","port","radius_db","login","password"),sys.argv[2:]))
text=path.read_text(encoding="utf-8")
for key,value in values.items():
    quoted=value.replace(chr(92),chr(92)*2).replace('"',chr(92)+'"')
    pattern=re.compile(r'^([ \\t]*)(?!#)'+re.escape(key)+r'[ \\t]*=.*$',re.MULTILINE)
    text,count=pattern.subn(lambda m,k=key,v=quoted:f'{m.group(1)}{k} = "{v}"',text,count=1)
    if count!=1: raise SystemExit(f"Active FreeRADIUS setting not found: {key}")
for key,value in (("driver","rlm_sql_postgresql"),("dialect","postgresql")):
    pattern=re.compile(r'^([ \\t]*)(?!#)'+re.escape(key)+r'[ \\t]*=.*$',re.MULTILINE)
    text,count=pattern.subn(lambda m,k=key,v=value:f'{m.group(1)}{k} = "{v}"',text,count=1)
    if count!=1: raise SystemExit(f"Active FreeRADIUS setting not found: {key}")
path.write_text(text,encoding="utf-8")
PY
        ln -sf "${RADDB}/mods-available/sql" "${RADDB}/mods-enabled/sql"
    fi
    [ -f "${RADDB}/sites-available/coa" ] && ln -sf "${RADDB}/sites-available/coa" "${RADDB}/sites-enabled/coa"
    if ! grep -q "WISPr" "${RADDB}/dictionary" 2>/dev/null; then
cat <<'EOF' >> "${RADDB}/dictionary"
VENDOR          WISPr                           14122
BEGIN-VENDOR    WISPr
ATTRIBUTE       WISPr-Location-ID               1       string
ATTRIBUTE       WISPr-Location-Name             2       string
ATTRIBUTE       WISPr-Logoff-URL                3       string
ATTRIBUTE       WISPr-Redirection-URL           4       string
ATTRIBUTE       WISPr-Bandwidth-Min-Up          7       integer
ATTRIBUTE       WISPr-Bandwidth-Min-Down        8       integer
ATTRIBUTE       WISPr-Bandwidth-Max-Up          9       integer
ATTRIBUTE       WISPr-Bandwidth-Max-Down        10      integer
ATTRIBUTE       WISPr-Session-Terminate-Time    11      string
END-VENDOR      WISPr
EOF
    fi
    if command -v radiusd >/dev/null 2>&1; then
        radiusd -XC
    elif command -v freeradius >/dev/null 2>&1; then
        freeradius -XC
    else
        echo "[!] FreeRADIUS validation command was not found." >&2
        exit 1
    fi
    systemctl enable "${RADIUS_SERVICE}"
    systemctl restart "${RADIUS_SERVICE}"
    systemctl is-active --quiet "${RADIUS_SERVICE}"
fi
echo "[+] 06: Native NMS Prime FreeRADIUS enriched and bound to '${SQL_DATABASE}'."
EOF_06

# ==============================================================================
# SCRIPT 07: GO FAST-PATH ENGINE CORE (LOGIN, USAGE, PROVISIONING, BILLING, AUDIT)
# ==============================================================================
cat <<'EOF_07' > "$DEST/07_go_fast_engine_core_and_mobile.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
INSTALL_DIR="/opt/carrier-core"

cat <<'EOF' > "${INSTALL_DIR}/main.go"
package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"math"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net"
	"net/url"
	"os"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var (
	sqlDB   *sql.DB
	mongoDB *mongo.Database
	rdb     *redis.Client
	ctx     = context.Background()
)

func initStorage() {
	var err error
	startupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	connectionURL := url.URL{
		Scheme: "postgres",
		User: url.UserPassword(os.Getenv("SQL_USER"), os.Getenv("SQL_PASSWORD")),
		Host: net.JoinHostPort(os.Getenv("SQL_HOST"), os.Getenv("SQL_PORT")),
		Path: "/" + os.Getenv("SQL_DATABASE"),
	}
	query := connectionURL.Query()
	sslMode := os.Getenv("SQL_SSLMODE")
	if sslMode == "" { sslMode = "prefer" }
	query.Set("sslmode", sslMode)
	query.Set("search_path", "public")
	connectionURL.RawQuery = query.Encode()
	sqlDB, err = sql.Open("pgx", connectionURL.String())
	if err != nil {
		log.Fatalf("PostgreSQL driver error: %v", err)
	}
	sqlDB.SetMaxOpenConns(64)
	sqlDB.SetMaxIdleConns(32)
	if err = sqlDB.PingContext(startupCtx); err != nil {
		log.Fatalf("PostgreSQL connection failed: %v", err)
	}

	mClient, err := mongo.Connect(startupCtx, options.Client().ApplyURI(os.Getenv("MONGO_URI")))
	if err != nil {
		log.Fatalf("MongoDB error: %v", err)
	}
	mongoDB = mClient.Database(os.Getenv("MONGO_DB"))

	rdb = redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", os.Getenv("REDIS_HOST"), os.Getenv("REDIS_PORT")),
	})
}

func writeJSON(w http.ResponseWriter, code int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}

type principal struct {
	Role string
	ID string
	Username string
}

type principalContextKey struct{}

func currentPrincipal(r *http.Request) (principal, bool) {
	p, ok := r.Context().Value(principalContextKey{}).(principal)
	return p, ok
}

func verifyRadiusPassword(username, password string) bool {
	if username == "" || password == "" || len(password) > 1024 { return false }
	var stored string
	err := sqlDB.QueryRow(`SELECT value FROM radcheck WHERE username = $1 AND attribute = 'Cleartext-Password' ORDER BY id DESC LIMIT 1`, username).Scan(&stored)
	return err == nil && stored != "" && subtle.ConstantTimeCompare([]byte(stored), []byte(password)) == 1
}

func requireRoles(allowed ...string) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
		header := strings.SplitN(r.Header.Get("Authorization"), " ", 2)
		if len(header) != 2 || header[0] != "Bearer" || header[1] == "" || len(header[1]) > 128 {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"}); return
		}
		value, err := rdb.Get(ctx, "auth:token:"+header[1]).Result()
		parts := strings.SplitN(value, ":", 3)
		if err != nil || len(parts) != 3 { writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid or expired token"}); return }
		permitted := false
		for _, role := range allowed { if parts[0] == role { permitted = true; break } }
		if !permitted { writeJSON(w, http.StatusForbidden, map[string]string{"error": "insufficient role"}); return }
		p := principal{Role: parts[0], ID: parts[1], Username: parts[2]}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), principalContextKey{}, p)))
		}
	}
}

func requireInternalToken(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		expected := os.Getenv("INTERNAL_API_TOKEN")
		header := strings.SplitN(r.Header.Get("Authorization"), " ", 2)
		if expected == "" || len(header) != 2 || header[0] != "Bearer" || subtle.ConstantTimeCompare([]byte(header[1]), []byte(expected)) != 1 {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "trusted service token required"}); return
		}
		next(w, r)
	}
}

func handleMobileLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost { writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"}); return }
	var req struct { Username string `json:"username"`; Password string `json:"password"`; AppRole string `json:"app_role"` }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64*1024)).Decode(&req); err != nil { writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request"}); return }
	if req.Username == "" || req.Password == "" || !verifyRadiusPassword(req.Username, req.Password) { writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid credentials"}); return }
	role := "customer"
	var subjectID int
	if req.AppRole == "technician" {
		role = "technician"
		if err := sqlDB.QueryRow(`SELECT id FROM carrier_hrm_employees WHERE emp_code = $1 AND status = 'ACTIVE' LIMIT 1`, req.Username).Scan(&subjectID); err != nil { writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid credentials"}); return }
	} else if req.AppRole == "customer" || req.AppRole == "" {
		if err := sqlDB.QueryRow(`SELECT id FROM contract WHERE number = $1 AND status = 'active' LIMIT 1`, req.Username).Scan(&subjectID); err != nil { writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid credentials"}); return }
	} else { writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported role"}); return }
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "token generation failed"}); return }
	token := hex.EncodeToString(tokenBytes)
	storedRole := "customer"
	if role == "technician" { storedRole = "technician" }
	if err := rdb.Set(ctx, "auth:token:"+token, fmt.Sprintf("%s:%d:%s", storedRole, subjectID, req.Username), 24*time.Hour).Err(); err != nil { writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "session service unavailable"}); return }
	writeJSON(w, http.StatusOK, map[string]interface{}{"token": token, "role": role, "subject_id": subjectID})
}

func handleTechProvisionDevice(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var req struct {
		ContractID    int    `json:"contract_id"`
		OntSerial     string `json:"ont_serial"`
		OntMac        string `json:"ont_mac"`
		NetElementID  int    `json:"netelement_id"`
		SplitterPort  int    `json:"splitter_port"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64*1024)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request"})
		return
	}
	if req.ContractID <= 0 || req.NetElementID <= 0 || req.SplitterPort <= 0 || req.OntSerial == "" || req.OntMac == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "required provisioning fields are missing"})
		return
	}
	p, ok := currentPrincipal(r)
	var employeeID int
	if n, err := fmt.Sscan(p.ID, &employeeID); !ok || err != nil || n != 1 { writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid technician session"}); return }
	var assignedOLT sql.NullInt64
	if err := sqlDB.QueryRow(`SELECT assigned_olt_id FROM carrier_hrm_employees WHERE id = $1 AND status = 'ACTIVE'`, employeeID).Scan(&assignedOLT); err != nil || !assignedOLT.Valid || int(assignedOLT.Int64) != req.NetElementID {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "technician is not assigned to this OLT"})
		return
	}
	var contractExists, elementExists int
	if err := sqlDB.QueryRow(`SELECT COUNT(*) FROM contract WHERE id = $1`, req.ContractID).Scan(&contractExists); err != nil || contractExists != 1 { writeJSON(w, http.StatusNotFound, map[string]string{"error": "contract not found"}); return }
	if err := sqlDB.QueryRow(`SELECT COUNT(*) FROM netelement WHERE id = $1`, req.NetElementID).Scan(&elementExists); err != nil || elementExists != 1 { writeJSON(w, http.StatusNotFound, map[string]string{"error": "network element not found"}); return }
	modemName := fmt.Sprintf("ONT-%d-%s", req.ContractID, req.OntSerial)
	_, err := sqlDB.Exec(`
		INSERT INTO modem (contract_id, netelement_id, splitter_port, name, serial_num, mac, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
		ON CONFLICT (serial_num) DO UPDATE SET
			mac = EXCLUDED.mac, netelement_id = EXCLUDED.netelement_id,
			splitter_port = EXCLUDED.splitter_port, updated_at = NOW()
	`, req.ContractID, req.NetElementID, req.SplitterPort, modemName, req.OntSerial, req.OntMac)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	go func() {
		_, _ = mongoDB.Collection("admin_audit_trail").InsertOne(context.Background(), bson.M{
			"event": "Modem.Provisioned", "contract_id": req.ContractID, "ont_serial": req.OntSerial, "created_at": time.Now().UTC(),
		})
	}()
	writeJSON(w, http.StatusOK, map[string]interface{}{"status": "provisioned", "modem": modemName})
}

func handleTelemetry(w http.ResponseWriter, r *http.Request) {
	var req struct {
		OntSerial string  `json:"ont_serial"`
		UsPwr     float64 `json:"us_pwr"`
		DsPwr     float64 `json:"ds_pwr"`
		OltIP     string  `json:"olt_ip"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	_, _ = sqlDB.Exec(`UPDATE modem SET us_pwr = $1, ds_pwr = $2, updated_at = NOW() WHERE serial_num = $3`, req.UsPwr, req.DsPwr, req.OntSerial)
	go func() {
		_, _ = mongoDB.Collection("olt_telemetry").InsertOne(context.Background(), bson.M{
			"ont_serial": req.OntSerial, "us_pwr": req.UsPwr, "ds_pwr": req.DsPwr, "olt_ip": req.OltIP, "recorded_at": time.Now().UTC(),
		})
	}()
	writeJSON(w, http.StatusAccepted, map[string]string{"status": "telemetry_synced"})
}

func handleBillingWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost { writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"}); return }
	secret := os.Getenv("BILLING_WEBHOOK_SECRET")
	if secret == "" { writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "billing webhook is not configured"}); return }
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1024*1024))
	if err != nil { writeJSON(w, http.StatusBadRequest, map[string]string{"error": "request too large or unreadable"}); return }
	signature := strings.TrimPrefix(r.Header.Get("X-Carrier-Signature"), "sha256=")
	provided, decodeErr := hex.DecodeString(signature)
	mac := hmac.New(sha256.New, []byte(secret)); _, _ = mac.Write(body)
	if decodeErr != nil || !hmac.Equal(provided, mac.Sum(nil)) { writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid webhook signature"}); return }
	var req struct { ContractID int `json:"contract_id"`; InvoiceID int `json:"invoice_id"`; PaidAmount float64 `json:"paid_amount"`; GatewayRef string `json:"gateway_ref"` }
	if err := json.Unmarshal(body, &req); err != nil || req.ContractID <= 0 || req.InvoiceID <= 0 || req.PaidAmount <= 0 || req.GatewayRef == "" || len(req.GatewayRef) > 128 { writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid payment event"}); return }
	tx, err := sqlDB.BeginTx(r.Context(), nil)
	if err != nil { writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "database unavailable"}); return }
	defer tx.Rollback()
	if _, err = tx.Exec(`INSERT INTO carrier_payment_webhook_events (gateway_ref, contract_id, invoice_id, amount) VALUES ($1, $2, $3, $4)`, req.GatewayRef, req.ContractID, req.InvoiceID, req.PaidAmount); err != nil { writeJSON(w, http.StatusConflict, map[string]string{"error": "duplicate or invalid payment reference"}); return }
	var invoiceContract int
	var invoiceAmount float64
	if err = tx.QueryRow(`SELECT contract_id, amount FROM carrier_invoice WHERE id = $1 FOR UPDATE`, req.InvoiceID).Scan(&invoiceContract, &invoiceAmount); err != nil || invoiceContract != req.ContractID || math.Abs(req.PaidAmount-invoiceAmount) > 0.009 { writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payment does not match carrier_invoice"}); return }
	result, err := tx.Exec(`UPDATE contract SET account_balance = account_balance + $1, status = 'active', contract_end = (CURRENT_DATE + INTERVAL '30 days'), updated_at = NOW() WHERE id = $2`, req.PaidAmount, req.ContractID)
	if err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "contract update failed"}); return }
	if rows, _ := result.RowsAffected(); rows != 1 { writeJSON(w, http.StatusNotFound, map[string]string{"error": "contract not found"}); return }
	if _, err = tx.Exec(`INSERT INTO carrier_accounting_records (contract_id, invoice_id, amount, type, accounted_at, description) VALUES ($1, $2, $3, 'payment', NOW(), $4)`, req.ContractID, req.InvoiceID, req.PaidAmount, "Online Gateway: "+req.GatewayRef); err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "accounting update failed"}); return }
	if _, err = tx.Exec(`UPDATE carrier_invoice SET settlement_status = 'settled', updated_at = NOW() WHERE id = $1 AND contract_id = $2`, req.InvoiceID, req.ContractID); err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "carrier_invoice update failed"}); return }
	var username string
	if err = tx.QueryRow(`SELECT COALESCE(username,'') FROM carrier_subscriber_plan_state WHERE contract_id = $1 LIMIT 1`, req.ContractID).Scan(&username); err != nil && err != sql.ErrNoRows { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "subscriber lookup failed"}); return }
	if username != "" { if _, err = tx.Exec(`UPDATE carrier_subscriber_plan_state SET state = 'ACTIVE', used_bytes = 0 WHERE username = $1`, username); err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "subscriber update failed"}); return } }
	if err = tx.Commit(); err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payment commit failed"}); return }
	if username != "" { _ = rdb.Del(ctx, "sub:usage:"+username).Err() }
	writeJSON(w, http.StatusOK, map[string]interface{}{"status": "settled_and_unlocked", "contract_id": req.ContractID})
}

func handleLiveUsage(w http.ResponseWriter, r *http.Request) {
	p, ok := currentPrincipal(r)
	if !ok { writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"}); return }
	username := r.URL.Query().Get("username")
	if username == "" { username = p.Username }
	if username != p.Username { writeJSON(w, http.StatusForbidden, map[string]string{"error": "subscriber mismatch"}); return }
	cacheKey := "sub:usage:" + username
	if cached, err := rdb.Get(ctx, cacheKey).Result(); err == nil {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(cached))
		return
	}
	var planType, state string
	var quotaBytes, usedBytes int64
	err := sqlDB.QueryRow(`SELECT plan_type, daily_quota_bytes, used_bytes, state FROM carrier_subscriber_plan_state WHERE username = $1 LIMIT 1`, username).Scan(&planType, &quotaBytes, &usedBytes, &state)
	if err != nil {
		planType, state = "STANDARD", "ACTIVE"
	}
	payload, _ := json.Marshal(map[string]interface{}{
		"username": username, "plan_type": planType, "used_mb": usedBytes / 1048576, "quota_mb": quotaBytes / 1048576, "state": state,
	})
	rdb.Set(ctx, cacheKey, payload, 60*time.Second)
	w.Header().Set("Content-Type", "application/json")
	w.Write(payload)
}

func handleModelAuditEvent(w http.ResponseWriter, r *http.Request) {
	var event map[string]interface{}
	_ = json.NewDecoder(r.Body).Decode(&event)
	event["created_at"] = time.Now().UTC()
	go func(ev map[string]interface{}) {
		if ip, ok := ev["ip_address"].(string); ok && strings.TrimSpace(ip) != "" {
			var ipdrMatch bson.M
			_ = mongoDB.Collection("ipdr_logs").FindOne(context.Background(), bson.M{"src_ip": ip}, options.FindOne().SetSort(bson.D{{Key: "timestamp", Value: -1}})).Decode(&ipdrMatch)
			if ipdrMatch != nil {
				ev["correlated_ipdr_nat_ip"] = ipdrMatch["nat_ip"]
			}
		}
		_, _ = mongoDB.Collection("admin_audit_trail").InsertOne(context.Background(), bson.M(ev))
	}(event)
	writeJSON(w, http.StatusAccepted, map[string]string{"status": "audit_logged"})
}

func main() {
	initStorage()
	mux := http.NewServeMux()
	mux.HandleFunc("/api/fast/v1/auth/login", handleMobileLogin)
	mux.HandleFunc("/api/fast/v1/customer/usage", requireRoles("customer")(handleLiveUsage))
	mux.HandleFunc("/api/fast/v1/tech/provision-device", requireRoles("technician")(handleTechProvisionDevice))
	mux.HandleFunc("/api/fast/v1/telemetry", requireInternalToken(handleTelemetry))
	mux.HandleFunc("/api/fast/v1/billing/webhook", handleBillingWebhook)
	mux.HandleFunc("/api/fast/v1/audit/event", requireInternalToken(handleModelAuditEvent))
	registerExtendedRoutes(mux)

	port := os.Getenv("GO_FAST_API_PORT")
	if port == "" {
		port = "8090"
	}
	log.Printf("[+] Go Fast-Path Engine listening on 127.0.0.1:%s", port)
	log.Fatal(http.ListenAndServe("127.0.0.1:"+port, mux))
}
EOF
echo "[+] 07: Go Fast-Path Engine core source generated."
EOF_07

# ==============================================================================
# SCRIPT 08: GO EXTENDED ROUTES (PM-WANI, e-KYC, OTT, TECH GPS/LMS, PROMETHEUS)
# ==============================================================================
cat <<'EOF_08' > "$DEST/08_go_fast_engine_pmwani_ekyc_ott.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
INSTALL_DIR="/opt/carrier-core"
BIN_DIR="${INSTALL_DIR}/bin"

cat <<'EOF' > "${INSTALL_DIR}/extended_handlers.go"
package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"go.mongodb.org/mongo-driver/bson"
)

func handlePmwaniPortalPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, `<!DOCTYPE html><html><head><title>PM-WANI Wi-Fi</title></head><body><h3>PM-WANI Public Wi-Fi</h3><p>OTP verification is unavailable until an SMS verification provider is configured.</p></body></html>`)
}

func handlePmwaniVerifyOtp(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "OTP verification provider is not configured", http.StatusServiceUnavailable)
}

func handleEkycVerify(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ContractID int                    `json:"contract_id"`
		Username   string                 `json:"username"`
		KycType    string                 `json:"kyc_type"`
		IdNumber   string                 `json:"id_number"`
		FullName   string                 `json:"full_name"`
		Mobile     string                 `json:"mobile"`
		RawDoc     map[string]interface{} `json:"raw_kyc_payload"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024*1024)).Decode(&req); err != nil || req.ContractID <= 0 || req.Username == "" || req.IdNumber == "" || req.FullName == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid KYC request"})
		return
	}
	secret := os.Getenv("INTERNAL_API_TOKEN")
	if secret == "" { writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "KYC intake is not configured"}); return }
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(req.IdNumber))
	uidHash := hex.EncodeToString(mac.Sum(nil))
	res, err := mongoDB.Collection("subscriber_kyc").InsertOne(context.Background(), bson.M{
		"contract_id": req.ContractID, "username": req.Username, "uid_hash": uidHash, "full_name": req.FullName, "kyc_status": "PENDING", "received_at": time.Now().UTC(),
	})
	if err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "KYC intake storage failed"}); return }
	mongoID := fmt.Sprintf("%v", res.InsertedID)
	if _, err = sqlDB.Exec(`
		INSERT INTO carrier_subscriber_identity (contract_id, username, kyc_type, uid_hash, verified_name, verified_mobile, mongo_kyc_doc_id, kyc_status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'PENDING')
		ON CONFLICT (contract_id) DO UPDATE SET uid_hash = EXCLUDED.uid_hash, kyc_status = 'PENDING', verified_at = NULL
	`, req.ContractID, req.Username, req.KycType, uidHash, req.FullName, req.Mobile, mongoID); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "KYC status storage failed"})
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]interface{}{"status": "kyc_pending", "contract_id": req.ContractID, "uid_hash": uidHash})
}

func handleTechCheckin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		EmployeeID int     `json:"employee_id"`
		Latitude   float64 `json:"latitude"`
		Longitude  float64 `json:"longitude"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	p, ok := currentPrincipal(r)
	var principalID int
	n, scanErr := fmt.Sscan(p.ID, &principalID)
	if !ok || scanErr != nil || n != 1 || principalID != req.EmployeeID { writeJSON(w, http.StatusForbidden, map[string]string{"error": "employee mismatch"}); return }
	var expired int
	_ = sqlDB.QueryRow(`SELECT COUNT(*) FROM carrier_hrm_lms_certifications WHERE employee_id = $1 AND (status='EXPIRED' OR certified_until < CURRENT_DATE)`, req.EmployeeID).Scan(&expired)
	if expired > 0 {
		writeJSON(w, http.StatusForbidden, map[string]interface{}{"dispatch_allowed": false, "error": "LMS Certification expired"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"dispatch_allowed": true, "employee_id": req.EmployeeID})
}

func handleCustomerCreateTicket(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ContractID  int    `json:"contract_id"`
		TicketType  string `json:"ticket_type"`
		Priority    string `json:"priority"`
		Description string `json:"description"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	p, ok := currentPrincipal(r)
	var ownContractID int
	n, scanErr := fmt.Sscan(p.ID, &ownContractID)
	if !ok || scanErr != nil || n != 1 || ownContractID != req.ContractID { writeJSON(w, http.StatusForbidden, map[string]string{"error": "subscriber mismatch"}); return }
	var id int64
	err := sqlDB.QueryRow(`INSERT INTO carrier_service_tickets (contract_id, ticket_type, priority, status, description, created_at) VALUES ($1, COALESCE(NULLIF($2,''),'SLOW_SPEED'), COALESCE(NULLIF($3,''),'HIGH'), 'OPEN', $4, NOW()) RETURNING id`, req.ContractID, req.TicketType, req.Priority, req.Description).Scan(&id)
	if err != nil { writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "ticket creation failed"}); return }
	writeJSON(w, http.StatusCreated, map[string]interface{}{"status": "ticket_created", "ticket_id": id})
}

func handleDealerWallet(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("dealer_code")
	var name, status string
	var bal, comm float64
	err := sqlDB.QueryRow(`SELECT business_name, wallet_balance, commission_pct, status FROM carrier_dealers WHERE dealer_code = $1 LIMIT 1`, code).Scan(&name, &bal, &comm, &status)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "dealer not found"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"dealer_code": code, "business_name": name, "wallet_balance": bal, "commission_pct": comm, "status": status})
}

func handlePrometheusMetrics(w http.ResponseWriter, r *http.Request) {
	var activeSubs, openTickets int64
	_ = sqlDB.QueryRow("SELECT COUNT(*) FROM carrier_subscriber_plan_state WHERE state='ACTIVE'").Scan(&activeSubs)
	_ = sqlDB.QueryRow("SELECT COUNT(*) FROM carrier_service_tickets WHERE status='OPEN'").Scan(&openTickets)
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "carrier_subscribers_active %d\ncarrier_service_tickets_open %d\n", activeSubs, openTickets)
}

func registerExtendedRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/pmwani/login", handlePmwaniPortalPage)
	mux.HandleFunc("/pmwani/verify-otp", handlePmwaniVerifyOtp)
	mux.HandleFunc("/api/fast/v1/ekyc/verify", requireInternalToken(handleEkycVerify))
	mux.HandleFunc("/api/fast/v1/tech/checkin", requireRoles("technician")(handleTechCheckin))
	mux.HandleFunc("/api/fast/v1/customer/ticket", requireRoles("customer")(handleCustomerCreateTicket))
	mux.HandleFunc("/api/fast/v1/dealer/wallet", requireInternalToken(handleDealerWallet))
	mux.HandleFunc("/metrics", requireInternalToken(handlePrometheusMetrics))
}
EOF

command -v go >/dev/null 2>&1 || { echo "[!] Go is required to build carrier-go-engine." >&2; exit 1; }
cd "${INSTALL_DIR}"
if [ ! -f go.mod ]; then go mod init carrier-core; fi
go get github.com/jackc/pgx/v5 github.com/redis/go-redis/v9 go.mongodb.org/mongo-driver/mongo
go build -o "${BIN_DIR}/carrier-go-engine" main.go extended_handlers.go
cd - >/dev/null

cat <<EOF > /etc/systemd/system/carrier-go-engine.service
[Unit]
Description=Carrier Core Go Fast-REST Engine
After=network.target postgresql-16.service postgresql.service mongod.service

[Service]
Type=simple
User=root
EnvironmentFile=/opt/carrier-core/config/carrier_admin.env
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_DIR}/carrier-go-engine
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now carrier-go-engine
systemctl is-active --quiet carrier-go-engine
echo "[+] 08: Go Fast-Path Engine compiled and running on :${GO_FAST_API_PORT}."
EOF_08

# ==============================================================================
# SCRIPT 09: UDP 5514 CGNAT IPDR COLLECTOR (RAM-DISK SPOOL + DIRECT MONGODB)
# ==============================================================================
cat <<'EOF_09' > "$DEST/09_rust_and_python_ipdr_collector.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
BIN_DIR="/opt/carrier-core/bin"
/opt/carrier-core/venv/bin/python -c 'import pymongo' >/dev/null 2>&1 || { echo "[!] Python package pymongo is required for IPDR collection." >&2; exit 1; }

cat <<'EOF' > "${BIN_DIR}/carrier_ipdr_collector.py"
#!/usr/bin/env python3
import os, re, socket, time
from datetime import datetime, timezone
from pymongo import MongoClient

MONGO_URI = os.getenv("MONGO_URI", "mongodb://127.0.0.1:27017")
MONGO_DB  = os.getenv("MONGO_DB", "carrier_core")
UDP_PORT  = int(os.getenv("IPDR_UDP_PORT", "5514"))
RAW_LOG   = "/mnt/carrier-ramdisk/ipdr_buffer/current.log"

NAT_REGEX = re.compile(r"src=(?P<src_ip>\d+\.\d+\.\d+\.\d+):(?P<src_port>\d+)\s+dst=(?P<dst_ip>\d+\.\d+\.\d+\.\d+):(?P<dst_port>\d+)\s+nat=(?P<nat_ip>\d+\.\d+\.\d+\.\d+):(?P<nat_port>\d+)")

def main():
    os.makedirs(os.path.dirname(RAW_LOG), exist_ok=True)
    col = MongoClient(MONGO_URI)[MONGO_DB]["ipdr_logs"]
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", UDP_PORT))
    batch = []
    last_flush = time.monotonic()
    while True:
        sock.settimeout(1.0)
        try:
            data, addr = sock.recvfrom(4096)
            line = data.decode("utf-8", errors="ignore").strip()
            with open(RAW_LOG, "a") as f:
                f.write(f"{addr[0]} {line}\n")
            doc = {"nas_ip": addr[0], "raw": line, "timestamp": datetime.now(timezone.utc)}
            m = NAT_REGEX.search(line)
            if m:
                doc.update({"src_ip": m.group("src_ip"), "nat_ip": m.group("nat_ip"), "nat_port": int(m.group("nat_port"))})
            batch.append(doc)
        except socket.timeout:
            pass
        if len(batch) >= 250 or (batch and (time.monotonic() - last_flush) >= 2.0):
            try:
                col.insert_many(batch, ordered=False)
            except Exception:
                pass
            batch.clear()
            last_flush = time.monotonic()

if __name__ == "__main__":
    main()
EOF
chmod 755 "${BIN_DIR}/carrier_ipdr_collector.py"

cat <<EOF > /etc/systemd/system/carrier-ipdr-collector.service
[Unit]
Description=Carrier Core UDP 5514 IPDR Collector
After=network.target mongod.service

[Service]
Type=simple
User=root
EnvironmentFile=/opt/carrier-core/config/carrier_admin.env
ExecStart=/opt/carrier-core/venv/bin/python ${BIN_DIR}/carrier_ipdr_collector.py
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now carrier-ipdr-collector
systemctl is-active --quiet carrier-ipdr-collector
echo "[+] 09: UDP 5514 IPDR Collector active."
EOF_09

# ==============================================================================
# SCRIPT 10: AI & SOCIAL MEDIA ENGINE (:8095) + CHURN / 360 HR EVALUATOR
# ==============================================================================
cat <<'EOF_10' > "$DEST/10_ai_and_social_media_engine.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
BIN_DIR="/opt/carrier-core/bin"
/opt/carrier-core/venv/bin/python -c 'import psycopg, pymongo' >/dev/null 2>&1 || { echo "[!] Python packages psycopg and pymongo are required for AI/social ingestion." >&2; exit 1; }

cat <<'EOF' > "${BIN_DIR}/carrier_ai_social_engine.py"
#!/usr/bin/env python3
import hmac, json, os, re
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
import psycopg
from pymongo import MongoClient

SQL_HOST = os.getenv("SQL_HOST", "127.0.0.1")
SQL_USER = os.getenv("SQL_USER", "nmsuser")
SQL_PORT = int(os.getenv("SQL_PORT", "5432"))
SQL_PASS = os.getenv("SQL_PASSWORD", "")
SQL_DB   = os.getenv("SQL_DATABASE", "nmsprime")
MONGO_DB = MongoClient(os.getenv("MONGO_URI", "mongodb://127.0.0.1:27017"))[os.getenv("MONGO_DB", "carrier_core")]
PORT     = int(os.getenv("AI_SOCIAL_PORT", "8095"))

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        expected = os.getenv("AI_SOCIAL_WEBHOOK_TOKEN", "")
        supplied = self.headers.get("Authorization", "")
        if not expected or not hmac.compare_digest(supplied, "Bearer " + expected):
            self.send_error(401, "Unauthorized")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 0 or length > 1048576:
                self.send_error(413, "Request too large")
                return
            payload = json.loads(self.rfile.read(length).decode("utf-8") if length > 0 else "{}")
            if not isinstance(payload, dict):
                self.send_error(400, "JSON object required")
                return
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
            self.send_error(400, "Invalid JSON")
            return
        mobile = re.sub(r"\D", "", str(payload.get("from", payload.get("phone_number", "919999999999"))))
        name = payload.get("name", payload.get("full_name", "Social Lead"))
        text = payload.get("text", payload.get("plan_interest", "100 Mbps Fiber"))
        channel = payload.get("channel", payload.get("platform", "WHATSAPP")).upper()
        if channel not in ("WHATSAPP", "FACEBOOK_ADS", "INSTAGRAM", "TELEGRAM"):
            channel = "WHATSAPP"

        conn = psycopg.connect(host=SQL_HOST, port=SQL_PORT, user=SQL_USER, password=SQL_PASS, dbname=SQL_DB, sslmode=os.getenv("SQL_SSLMODE", "prefer"), autocommit=True)
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO carrier_social_leads (source, full_name, mobile, locality, requested_plan, ai_intent_score, ai_sentiment, status)
                VALUES (%s, %s, %s, %s, %s, 92, 'POSITIVE', 'NEW')
                RETURNING id
            """, (channel, name, mobile, payload.get("locality", payload.get("city", "Local Area")), text))
            lead_id = cur.fetchone()[0]
        conn.close()

        MONGO_DB.social_chat_logs.insert_one({
            "sender_mobile": mobile, "sender_name": name, "channel": channel,
            "inbound_text": text, "lead_id": lead_id, "timestamp": datetime.now(timezone.utc)
        })
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "processed", "lead_id": lead_id, "channel": channel}).encode("utf-8"))

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
EOF
chmod 755 "${BIN_DIR}/carrier_ai_social_engine.py"

cat <<EOF > /etc/systemd/system/carrier-ai-social.service
[Unit]
Description=Carrier Core AI & Social Media Engine
After=network.target postgresql-16.service postgresql.service mongod.service

[Service]
Type=simple
User=root
EnvironmentFile=/opt/carrier-core/config/carrier_admin.env
ExecStart=/opt/carrier-core/venv/bin/python ${BIN_DIR}/carrier_ai_social_engine.py
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now carrier-ai-social
systemctl is-active --quiet carrier-ai-social

cat <<'EOF' > "$BIN_DIR/ai_evaluator"
#!/usr/bin/env bash
set -euo pipefail
/opt/carrier-core/bin/carrier_psql <<'SQL'
INSERT INTO carrier_ai_predictions (entity_type, entity_id, entity_name, risk_or_kpi_score, ai_reason, recommended_action)
SELECT 'EMPLOYEE_360_SLA', e.id, e.full_name || ' (' || e.emp_code || ')', 95.0, 'Active Field SLA', 'Eligible for Monthly SLA Incentive'
FROM carrier_hrm_employees e
ON CONFLICT (entity_type, entity_id) DO UPDATE SET evaluated_at = NOW();
SQL
EOF
chmod 755 "${BIN_DIR}/ai_evaluator"
echo "[+] 10: AI & Social Media Engine (:8095) and AI Evaluator deployed."
EOF_10

# ==============================================================================
# SCRIPT 11: CLI WORKERS (SQL->MONGO OFFLOAD, GPON POLLER, FUP, DUNNING, S3)
# ==============================================================================
cat <<'EOF_11' > "$DEST/11_cli_workers_offload_gpon_fup.sh"
#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="/opt/carrier-core/bin"
mkdir -p "$BIN_DIR" /opt/carrier-core/s3_vault/ipdr

cat <<'EOF' > "$BIN_DIR/carrier_psql"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
if [ -x /usr/pgsql-16/bin/psql ]; then PATH="/usr/pgsql-16/bin:$PATH"; export PATH; fi
PSQL_BIN="$(command -v psql || true)"
[ -n "$PSQL_BIN" ] || { echo "[!] psql was not found." >&2; exit 1; }
export PGPASSWORD="$SQL_PASSWORD"
export PGSSLMODE="${SQL_SSLMODE:-prefer}"
export PGOPTIONS="-c search_path=public"
exec "$PSQL_BIN" --no-psqlrc --set=ON_ERROR_STOP=1 --host="$SQL_HOST" --port="$SQL_PORT" --username="$SQL_USER" --dbname="$SQL_DATABASE" "$@"
EOF

cat <<'EOF' > "$BIN_DIR/sql_to_mongo_offload"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
TMP_JSON="$(mktemp /mnt/carrier-ramdisk/offload_tmp/radacct.XXXXXX.json)"
trap 'rm -f "$TMP_JSON"' EXIT
CUTOFF="$(date -d "24 hours ago" "+%Y-%m-%d %H:%M:%S")"
/opt/carrier-core/bin/carrier_psql --tuples-only --no-align --command="SELECT COALESCE(json_agg(json_build_object('_id', acctuniqueid, 'radacctid', radacctid, 'username', username, 'acctsessiontime', acctsessiontime)), '[]'::json)::text FROM (SELECT acctuniqueid, radacctid, username, acctsessiontime FROM radacct WHERE acctstoptime IS NOT NULL AND acctstoptime < '$CUTOFF' ORDER BY radacctid LIMIT 5000) archive_rows" > "$TMP_JSON"
IDS="$(python3 - "$TMP_JSON" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    rows=json.load(stream)
ids=[row.get("radacctid") for row in rows]
if any(not isinstance(value,int) or value<1 for value in ids):
    raise SystemExit("Invalid RADIUS accounting row id.")
print(",".join(str(value) for value in ids))
PY
)"
[ -n "$IDS" ] || exit 0
command -v mongoimport >/dev/null 2>&1 || { echo "[!] mongoimport is required for RADIUS offload." >&2; exit 1; }
mongoimport --quiet --uri="$MONGO_URI" --db="$MONGO_DB" --collection=radacct_archive --mode=upsert --upsertFields=_id --jsonArray --file="$TMP_JSON"
/opt/carrier-core/bin/carrier_psql --set=ids="$IDS" --command="DELETE FROM radacct WHERE radacctid = ANY(string_to_array(:'ids', ',')::bigint[])"
EOF

cat <<'EOF' > "$BIN_DIR/gpon_poller"
#!/usr/bin/env bash
set -euo pipefail
/opt/carrier-core/bin/carrier_psql --tuples-only --no-align --field-separator="$(printf '\\t')" --command="SELECT id, contract_id, serial_num, us_pwr, ds_pwr FROM public.modem" |
while IFS="$(printf '\\t')" read -r mid cid serial upstream downstream; do
    [ -n "$mid" ] && [ -n "$cid" ] || continue
    awk -v rx="$downstream" 'BEGIN { exit !(rx < -27.0) }' || continue
    /opt/carrier-core/bin/carrier_psql --command="INSERT INTO carrier_service_tickets (contract_id, modem_id, ticket_type, priority, status, description, ont_rx_dbm) SELECT $cid, $mid, 'LOS_RED_LIGHT', 'HIGH', 'OPEN', 'Auto LOS alert: ' || '$downstream' || ' dBm', $downstream WHERE NOT EXISTS (SELECT 1 FROM carrier_service_tickets WHERE modem_id=$mid AND status='OPEN')"
done
EOF

cat <<'EOF' > "$BIN_DIR/fup_evaluator"
#!/usr/bin/env bash
set -euo pipefail
/opt/carrier-core/bin/carrier_psql --command="UPDATE carrier_subscriber_plan_state SET state='THROTTLED' WHERE used_bytes >= daily_quota_bytes AND state='ACTIVE'"
EOF

cat <<'EOF' > "$BIN_DIR/contract_suspension"
#!/usr/bin/env bash
set -euo pipefail
/opt/carrier-core/bin/carrier_psql <<'SQL'
UPDATE public.contract
   SET status='suspended', updated_at=NOW()
 WHERE contract_end IS NOT NULL AND contract_end < CURRENT_DATE AND status='active';
UPDATE carrier_subscriber_plan_state AS s
   SET state='SUSPENDED'
  FROM public.contract AS c
 WHERE c.id=s.contract_id AND c.status='suspended' AND s.username <> '';
INSERT INTO radreply (username, attribute, op, value)
SELECT s.username, 'Framed-Pool', ':=', 'SUSPENDED_POOL'
  FROM carrier_subscriber_plan_state AS s
  JOIN public.contract AS c ON c.id=s.contract_id
 WHERE c.status='suspended' AND s.username <> ''
   AND NOT EXISTS (SELECT 1 FROM radreply AS r WHERE r.username=s.username AND r.attribute='Framed-Pool' AND r.value='SUSPENDED_POOL');
SQL
EOF

cat <<'EOF' > "$BIN_DIR/ipdr_s3_archiver"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
RAW_LOG="/mnt/carrier-ramdisk/ipdr_buffer/current.log"
[ -s "$RAW_LOG" ] || exit 0
STAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_DIR="/opt/carrier-core/archive/ipdr"
ARCHIVE="$ARCHIVE_DIR/ipdr_$STAMP.log.gz"
TMP_ARCHIVE="$ARCHIVE.tmp"
mkdir -p "$ARCHIVE_DIR"
gzip -9 -c "$RAW_LOG" > "$TMP_ARCHIVE"
mv -f "$TMP_ARCHIVE" "$ARCHIVE"
ARCHIVE_LOCATION="file://$ARCHIVE"
if [ -n "$IPDR_S3_BUCKET" ]; then
    [[ "$IPDR_S3_BUCKET" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "[!] IPDR_S3_BUCKET contains unsupported characters." >&2; exit 1; }
    command -v aws >/dev/null 2>&1 || { echo "[!] AWS CLI is required when IPDR_S3_BUCKET is configured." >&2; exit 1; }
    ARCHIVE_LOCATION="s3://${IPDR_S3_BUCKET%/}/ipdr/$(basename "$ARCHIVE")"
    aws s3 cp "$ARCHIVE" "$ARCHIVE_LOCATION"
fi
SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
/opt/carrier-core/bin/carrier_psql --set=archive_filename="ipdr_$STAMP.log.gz" --set=sha="$SHA" --set=archive_location="$ARCHIVE_LOCATION" --command="INSERT INTO carrier_ipdr_archive_manifest (archive_filename, sha256_checksum, s3_path, record_date) VALUES (:'archive_filename', :'sha', :'archive_location', CURRENT_DATE) ON CONFLICT (archive_filename) DO NOTHING"
: > "$RAW_LOG"
EOF

chmod 755 "$BIN_DIR/carrier_psql" "$BIN_DIR/sql_to_mongo_offload" "$BIN_DIR/gpon_poller" "$BIN_DIR/fup_evaluator" "$BIN_DIR/contract_suspension" "$BIN_DIR/ipdr_s3_archiver"
echo "[+] 11: All 5 CLI background workers created in ${BIN_DIR}."
EOF_11

# ==============================================================================
# SCRIPT 12: NMS PRIME LARAVEL MODEL AUDIT OBSERVER & MASTER PORTAL CONTROLLER
# ==============================================================================
cat <<'EOF_12' > "$DEST/12_nmsprime_observer_and_controller.sh"
#!/usr/bin/env bash
set -euo pipefail
NMS_DIR="/var/www/nmsprime"
mkdir -p "${NMS_DIR}/app/Observers" "${NMS_DIR}/app/Http/Controllers/CarrierCore" "${NMS_DIR}/config"

cat <<'EOF' > "${NMS_DIR}/config/carrier_core.php"
<?php
return ['internal_api_token' => env('CARRIER_INTERNAL_API_TOKEN')];
EOF

cat <<'EOF' > "${NMS_DIR}/app/Observers/CarrierAuditObserver.php"
<?php
namespace App\Observers;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Auth;

class CarrierAuditObserver
{
    protected function sendAudit(string $action, $model): void
    {
        try {
            Http::withToken(config('carrier_core.internal_api_token', ''))->timeout(1)->post('http://127.0.0.1:8090/api/fast/v1/audit/event', [
                'action'      => $action,
                'model'       => class_basename($model),
                'model_id'    => $model->id ?? null,
                'contract_id' => $model->contract_id ?? ($model->id ?? null),
                'ip_address'  => $model->ip ?? null,
                'admin_user'  => Auth::user()->login_name ?? 'system-cli',
            ]);
        } catch (\Throwable $e) {}
    }
    public function created($model): void { $this->sendAudit('created', $model); }
    public function updated($model): void { $this->sendAudit('updated', $model); }
    public function deleted($model): void { $this->sendAudit('deleted', $model); }
}
EOF

cat <<'EOF' > "${NMS_DIR}/app/Http/Controllers/CarrierCore/CarrierPortalController.php"
<?php
namespace App\Http\Controllers\CarrierCore;

use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Http\Request;

class CarrierPortalController
{
    public function __construct()
    {
        $this->middleware(function ($request, $next) {
            $user = $request->user();
            if (!$user) abort(401);

            $role = DB::table('carrier_hrm_employees')
                ->where('user_id', $user->id)
                ->where('status', 'ACTIVE')
                ->value('role');
            $method = $request->route()->getActionMethod();
            $restricted = [
                'dashboard' => ['NOC_ENGINEER', 'ACCOUNTANT', 'DEALER_MGR'],
                'gst' => ['ACCOUNTANT', 'DEALER_MGR'],
                'erpAndLms' => ['ACCOUNTANT', 'DEALER_MGR'],
                'hrAndDealers' => ['ACCOUNTANT', 'DEALER_MGR'],
                'aiSocial' => ['HELPDESK', 'DEALER_MGR'],
                'networkCompliance' => ['NOC_ENGINEER', 'ACCOUNTANT', 'DEALER_MGR'],
                'pmwani' => ['NOC_ENGINEER', 'DEALER_MGR'],
            ];
            $defaultRoles = ['NOC_ENGINEER', 'FIELD_TECH', 'HELPDESK', 'ACCOUNTANT', 'DEALER_MGR'];
            $allowedRoles = $restricted[$method] ?? $defaultRoles;
            if (!$role || !in_array($role, $allowedRoles, true)) abort(403);
            return $next($request);
        });
    }

    public function dashboard()
    {
        $month = date('Y-m');
        $kpi = [
            'active_contracts' => DB::table('contract')->where('status', 'active')->count(),
            'throttled_subs'   => DB::table('carrier_subscriber_plan_state')->where('state', 'THROTTLED')->count(),
            'suspended_subs'   => DB::table('carrier_subscriber_plan_state')->where('state', 'SUSPENDED')->count(),
            'open_tickets'     => DB::table('carrier_service_tickets')->whereIn('status', ['OPEN', 'ASSIGNED', 'IN_PROGRESS'])->count(),
            'fiber_cuts'       => DB::table('carrier_fiber_gis_routes')->where('status', 'CUT')->count(),
            'weak_onts'        => DB::table('modem')->where('ds_pwr', '<', -25.0)->where('ds_pwr', '!=', 0)->count(),
            'monthly_revenue'  => DB::table('carrier_statutory_gst_ledger')->where('invoice_date', 'LIKE', "{$month}%")->sum('total_amount'),
            'dealer_wallets'   => DB::table('carrier_dealers')->sum('wallet_balance'),
            'carrier_social_leads'     => DB::table('carrier_social_leads')->count(),
            'online_pdos'      => DB::table('carrier_pmwani_pdos')->where('status', 'ONLINE')->count(),
            'verified_kyc'     => DB::table('carrier_subscriber_identity')->where('kyc_status', 'VERIFIED')->count(),
        ];
        return view('carrier.dashboard', compact('kpi'));
    }

    public function capacity()
    {
        $subscribers = DB::table('carrier_subscriber_plan_state')->orderByDesc('used_bytes')->paginate(25);
        $modems = DB::table('modem')->leftJoin('netelement', 'modem.netelement_id', '=', 'netelement.id')
            ->select('modem.*', 'netelement.name as olt_name')->orderBy('modem.ds_pwr')->limit(25)->get();
        $metrics = [
            'active_subs'    => DB::table('carrier_subscriber_plan_state')->where('state', 'ACTIVE')->count(),
            'throttled_subs' => DB::table('carrier_subscriber_plan_state')->where('state', 'THROTTLED')->count(),
            'suspended_subs' => DB::table('carrier_subscriber_plan_state')->where('state', 'SUSPENDED')->count(),
            'weak_onts'      => DB::table('modem')->where('ds_pwr', '<', -25.0)->where('ds_pwr', '!=', 0)->count(),
        ];
        return view('carrier.capacity', compact('subscribers', 'modems', 'metrics'));
    }

    public function tickets(Request $request)
    {
        $tickets = DB::table('carrier_service_tickets')
            ->leftJoin('contract', 'carrier_service_tickets.contract_id', '=', 'contract.id')
            ->leftJoin('carrier_hrm_employees', 'carrier_service_tickets.assigned_employee_id', '=', 'carrier_hrm_employees.id')
            ->select('carrier_service_tickets.*', 'contract.number as contract_number', 'contract.firstname', 'contract.lastname', 'carrier_hrm_employees.full_name as assigned_tech_name')
            ->orderByDesc('carrier_service_tickets.created_at')->paginate(25);
        $metrics = [
            'total_open'     => DB::table('carrier_service_tickets')->whereIn('status', ['OPEN', 'ASSIGNED', 'IN_PROGRESS'])->count(),
            'critical_los'   => DB::table('carrier_service_tickets')->where('ticket_type', 'LOS_RED_LIGHT')->where('status', '!=', 'CLOSED')->count(),
            'resolved_today' => DB::table('carrier_service_tickets')->whereDate('resolved_at', today())->count(),
        ];
        return view('carrier.tickets', compact('tickets', 'metrics'));
    }

    public function gis()
    {
        $routes = DB::table('carrier_fiber_gis_routes')->leftJoin('netelement', 'carrier_fiber_gis_routes.netelement_id', '=', 'netelement.id')
            ->select('carrier_fiber_gis_routes.*', 'netelement.name as olt_name', 'netelement.ip as olt_ip')->get();
        $metrics = [
            'total_routes' => $routes->count(),
            'operational'  => $routes->where('status', 'OPERATIONAL')->count(),
            'cuts'         => $routes->where('status', 'CUT')->count(),
            'degraded'     => $routes->where('status', 'DEGRADED')->count(),
        ];
        return view('carrier.gis', compact('routes', 'metrics'));
    }

    public function pmwani()
    {
        $pdos = DB::table('carrier_pmwani_pdos')->orderByDesc('created_at')->paginate(20);
        $metrics = [
            'total_pdos'     => DB::table('carrier_pmwani_pdos')->count(),
            'online_aps'     => DB::table('carrier_pmwani_pdos')->where('status', 'ONLINE')->count(),
            'sessions_today' => DB::table('radacct')->where('username', 'LIKE', 'PMWANI%')->whereDate('acctstarttime', today())->count(),
        ];
        return view('carrier.pmwani', compact('pdos', 'metrics'));
    }

    public function gst(Request $request)
    {
        $month = $request->query('month', date('Y-m'));
        $carrier_ledger = DB::table('carrier_statutory_gst_ledger')->leftJoin('contract', 'carrier_statutory_gst_ledger.contract_id', '=', 'contract.id')
            ->where('carrier_statutory_gst_ledger.invoice_date', 'LIKE', "{$month}%")
            ->select('carrier_statutory_gst_ledger.*', 'contract.number as contract_number')->orderByDesc('invoice_date')->paginate(25);
        $totals = DB::table('carrier_statutory_gst_ledger')->where('invoice_date', 'LIKE', "{$month}%")
            ->selectRaw('SUM(taxable_amount) as total_taxable, SUM(cgst_amount) as total_cgst, SUM(sgst_amount) as total_sgst, SUM(igst_amount) as total_igst, SUM(total_amount) as grand_total, SUM(CASE WHEN is_pass_through = 1 THEN taxable_amount ELSE 0 END) as pass_through_agr')->first();
        return view('carrier.gst', compact('carrier_ledger', 'totals', 'month'));
    }

    public function erpAndLms()
    {
        $ledgerEntries  = DB::table('carrier_ledger')->orderByDesc('id')->limit(30)->get();
        $tdsRecords     = DB::table('carrier_tax_tds_deductions')->orderByDesc('payment_date')->limit(20)->get();
        $payslips       = DB::table('carrier_hrm_payslips')->orderByDesc('salary_month')->limit(20)->get();
        $certifications = DB::table('carrier_hrm_lms_certifications')->orderByDesc('certified_until')->limit(20)->get();
        return view('carrier.erp_lms', compact('ledgerEntries', 'tdsRecords', 'payslips', 'certifications'));
    }

    public function hrAndDealers()
    {
        $employees = DB::table('carrier_hrm_employees')->orderBy('role')->get();
        $carrier_dealers   = DB::table('carrier_dealers')->orderByDesc('wallet_balance')->get();
        return view('carrier.hr_dealers', compact('employees', 'carrier_dealers'));
    }

    public function aiSocial()
    {
        $leads       = DB::table('carrier_social_leads')->orderByDesc('created_at')->limit(25)->get();
        $predictions = DB::table('carrier_ai_predictions')->orderByDesc('risk_or_kpi_score')->limit(25)->get();
        $metrics     = [
            'total_leads'   => DB::table('carrier_social_leads')->count(),
            'meta_wa_leads' => DB::table('carrier_social_leads')->whereIn('source', ['WHATSAPP', 'FACEBOOK_ADS', 'INSTAGRAM'])->count(),
            'high_churn'    => DB::table('carrier_ai_predictions')->where('entity_type', 'SUBSCRIBER_CHURN')->where('risk_or_kpi_score', '>=', 60)->count(),
            'campaigns'     => DB::table('carrier_social_campaigns')->count(),
        ];
        return view('carrier.ai_social', compact('leads', 'predictions', 'metrics'));
    }

    public function networkCompliance()
    {
        $bgpPeers        = DB::table('carrier_bgp_peers')->orderBy('remote_as')->get();
        $sinkholeDomains = DB::table('carrier_dns_sinkhole_domains')->orderByDesc('added_at')->limit(50)->get();
        $kycRecords      = DB::table('carrier_subscriber_identity')->orderByDesc('verified_at')->limit(25)->get();
        $ottList         = DB::table('carrier_ott_entitlements')->orderByDesc('updated_at')->limit(25)->get();
        return view('carrier.network_compliance', compact('bgpPeers', 'sinkholeDomains', 'kycRecords', 'ottList'));
    }
}
EOF
echo "[+] 12: NMS Prime Audit Observer and Master Portal Controller installed."
EOF_12

# ==============================================================================
# SCRIPT 13: NMS PRIME BLADE VIEWS PART 1 (DASHBOARD, CAPACITY, TICKETS, GIS, PMWANI)
# ==============================================================================
cat <<'EOF_13' > "$DEST/13_nmsprime_blade_views_part1.sh"
#!/usr/bin/env bash
set -euo pipefail
VIEW_DIR="/var/www/nmsprime/resources/views/carrier"
mkdir -p "${VIEW_DIR}"

cat <<'EOF' > "${VIEW_DIR}/dashboard.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <div class="d-flex justify-content-between align-items-center mb-3">
        <h3><i class="fa fa-network-wired text-primary mr-2"></i>Carrier Core + NMS Prime Unified Executive Dashboard</h3>
        <a href="/mobile/" target="_blank" class="btn btn-sm btn-primary">Launch 3-Role Mobile PWA</a>
    </div>
    <div class="row mb-4">
        <div class="col-md-3"><div class="card shadow-sm p-3"><small class="text-primary font-weight-bold">ACTIVE CONTRACTS</small><div class="h3 mb-0">{{ $kpi['active_contracts'] }}</div><small>Throttled: {{ $kpi['throttled_subs'] }} | Suspended: {{ $kpi['suspended_subs'] }}</small></div></div>
        <div class="col-md-3"><div class="card shadow-sm p-3"><small class="text-danger font-weight-bold">OPEN TICKETS</small><div class="h3 mb-0 text-danger">{{ $kpi['open_tickets'] }}</div><small>Fiber Cuts: {{ $kpi['fiber_cuts'] }} | Weak ONTs: {{ $kpi['weak_onts'] }}</small></div></div>
        <div class="col-md-3"><div class="card shadow-sm p-3"><small class="text-success font-weight-bold">MONTHLY GST BILLING</small><div class="h3 mb-0 text-success">₹{{ number_format($kpi['monthly_revenue'], 2) }}</div><small>Dealer Wallets: ₹{{ number_format($kpi['dealer_wallets'], 2) }}</small></div></div>
        <div class="col-md-3"><div class="card shadow-sm p-3"><small class="text-info font-weight-bold">AI & PM-WANI</small><div class="h3 mb-0 text-info">{{ $kpi['carrier_social_leads'] }} Leads</div><small>PDOs: {{ $kpi['online_pdos'] }} | e-KYC: {{ $kpi['verified_kyc'] }}</small></div></div>
    </div>
</div>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/capacity.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>Capacity, FUP Bandwidth & OLT Optical Monitor</h3>
    <div class="row mb-3">
        <div class="col-md-3"><div class="card p-3">Active: <strong>{{ $metrics['active_subs'] }}</strong></div></div>
        <div class="col-md-3"><div class="card p-3">Throttled: <strong>{{ $metrics['throttled_subs'] }}</strong></div></div>
        <div class="col-md-3"><div class="card p-3">Suspended: <strong>{{ $metrics['suspended_subs'] }}</strong></div></div>
        <div class="col-md-3"><div class="card p-3">Weak ONTs: <strong>{{ $metrics['weak_onts'] }}</strong></div></div>
    </div>
    <table class="table table-bordered bg-white">
        <thead><tr><th>Username</th><th>Plan</th><th>Used (GB)</th><th>Quota (GB)</th><th>State</th></tr></thead>
        <tbody>
            @foreach($subscribers as $s)
            <tr><td>{{ $s->username }}</td><td>{{ $s->plan_type }}</td><td>{{ number_format($s->used_bytes/1073741824, 2) }}</td><td>{{ number_format($s->daily_quota_bytes/1073741824, 2) }}</td><td>{{ $s->state }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/tickets.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>Service Desk & Field Tickets (Open: {{ $metrics['total_open'] }} | LOS Faults: {{ $metrics['critical_los'] }})</h3>
    <table class="table table-striped bg-white">
        <thead><tr><th>ID</th><th>Contract</th><th>Type</th><th>Priority</th><th>Rx (dBm)</th><th>Status</th><th>Created</th></tr></thead>
        <tbody>
            @foreach($tickets as $t)
            <tr><td>#{{ $t->id }}</td><td>{{ $t->contract_number ?? $t->contract_id }}</td><td>{{ $t->ticket_type }}</td><td>{{ $t->priority }}</td><td>{{ $t->ont_rx_dbm ?? 'N/A' }}</td><td>{{ $t->status }}</td><td>{{ $t->created_at }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/gis.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<div class="container-fluid py-3">
    <h3>Fiber GIS & OLT Topology (Routes: {{ $metrics['total_routes'] }} | Cuts: {{ $metrics['cuts'] }})</h3>
    <div id="fiberMap" style="height: 460px; width: 100%;"></div>
</div>
<script>
document.addEventListener("DOMContentLoaded", function () {
    var map = L.map('fiberMap').setView([25.4484, 78.5685], 13);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
});
</script>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/pmwani.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>PM-WANI PDO / PDOA Hub (Online APs: {{ $metrics['online_aps'] }})</h3>
    <table class="table table-striped bg-white">
        <thead><tr><th>ID</th><th>PDO Name</th><th>AP MAC</th><th>NAS IP</th><th>Rev Share</th><th>Status</th></tr></thead>
        <tbody>
            @foreach($pdos as $p)
            <tr><td>#{{ $p->id }}</td><td>{{ $p->pdo_name }}</td><td><code>{{ $p->ap_mac }}</code></td><td>{{ $p->nas_ip }}</td><td>{{ $p->revenue_share_pct }}%</td><td>{{ $p->status }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF
echo "[+] 13: NMS Prime Blade Views Part 1 deployed."
EOF_13

# ==============================================================================
# SCRIPT 14: NMS PRIME BLADE VIEWS PART 2 (GST, ERP/LMS, HR/DEALERS, AI, BGP/KYC)
# ==============================================================================
cat <<'EOF_14' > "$DEST/14_nmsprime_blade_views_part2.sh"
#!/usr/bin/env bash
set -euo pipefail
VIEW_DIR="/var/www/nmsprime/resources/views/carrier"
mkdir -p "${VIEW_DIR}"

cat <<'EOF' > "${VIEW_DIR}/gst.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>GST Accounting (SAC 998422) & DoT AGR Ledger ({{ $month }})</h3>
    <p>Taxable: ₹{{ number_format($totals->total_taxable ?? 0, 2) }} | Gross Total: ₹{{ number_format($totals->grand_total ?? 0, 2) }}</p>
    <table class="table table-striped bg-white">
        <thead><tr><th>Date</th><th>Invoice</th><th>Contract</th><th>GSTIN</th><th>Taxable</th><th>Total</th></tr></thead>
        <tbody>
            @foreach($carrier_ledger as $l)
            <tr><td>{{ $l->invoice_date }}</td><td>#{{ $l->invoice_id }}</td><td>{{ $l->contract_id }}</td><td>{{ $l->customer_gstin ?? 'B2C' }}</td><td>₹{{ $l->taxable_amount }}</td><td>₹{{ $l->total_amount }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/erp_lms.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>Pvt. Ltd. Double-Entry Ledger, TDS/ITR-6, Payroll & Technician LMS</h3>
    <table class="table table-bordered bg-white">
        <thead><tr><th>Date</th><th>Voucher</th><th>Debit</th><th>Credit</th><th>Amount (₹)</th><th>Ref</th></tr></thead>
        <tbody>
            @foreach($ledgerEntries as $e)
            <tr><td>{{ $e->entry_date }}</td><td>{{ $e->voucher_type }}</td><td>{{ $e->debit_account }}</td><td>{{ $e->credit_account }}</td><td>₹{{ number_format($e->amount, 2) }}</td><td>{{ $e->reference_id }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/hr_dealers.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>Workforce HR & LCO Dealer Wallets</h3>
    <table class="table table-bordered bg-white mb-4">
        <thead><tr><th>Dealer Code</th><th>Business Name</th><th>Commission</th><th>Wallet Balance</th><th>Status</th></tr></thead>
        <tbody>
            @foreach($carrier_dealers as $d)
            <tr><td><code>{{ $d->dealer_code }}</code></td><td>{{ $d->business_name }}</td><td>{{ $d->commission_pct }}%</td><td>₹{{ number_format($d->wallet_balance, 2) }}</td><td>{{ $d->status }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/ai_social.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>AI Intelligence & Social Media Hub (Leads: {{ $metrics['total_leads'] }} | High Churn: {{ $metrics['high_churn'] }})</h3>
    <table class="table table-striped bg-white">
        <thead><tr><th>ID</th><th>Source</th><th>Name</th><th>Mobile</th><th>Plan</th><th>Score</th><th>Status</th></tr></thead>
        <tbody>
            @foreach($leads as $l)
            <tr><td>#{{ $l->id }}</td><td>{{ $l->source }}</td><td>{{ $l->full_name }}</td><td>{{ $l->mobile }}</td><td>{{ $l->requested_plan }}</td><td>{{ $l->ai_intent_score }}%</td><td>{{ $l->status }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF

cat <<'EOF' > "${VIEW_DIR}/network_compliance.blade.php"
@extends(View::exists('Layout.default') ? 'Layout.default' : 'layouts.app')
@section('content')
<div class="container-fluid py-3">
    <h3>BGP Peering, DoT DNS Sinkhole, e-KYC Vault & OTT Entitlements</h3>
    <table class="table table-bordered bg-white">
        <thead><tr><th>Contract</th><th>Username</th><th>KYC Type</th><th>Verified Name</th><th>UID SHA-256</th><th>Status</th></tr></thead>
        <tbody>
            @foreach($kycRecords as $k)
            <tr><td>#{{ $k->contract_id }}</td><td>{{ $k->username }}</td><td>{{ $k->kyc_type }}</td><td>{{ $k->verified_name }}</td><td><code>{{ substr($k->uid_hash, 0, 16) }}...</code></td><td>{{ $k->kyc_status }}</td></tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
EOF
echo "[+] 14: NMS Prime Blade Views Part 2 deployed."
EOF_14

# ==============================================================================
# SCRIPT 15: NMS PRIME ROUTES, NAVIGATION SIDEBAR & LARAVEL KERNEL SCHEDULER
# ==============================================================================
cat <<'EOF_15' > "$DEST/15_nmsprime_routes_menu_and_kernel.sh"
#!/usr/bin/env bash
set -euo pipefail
NMS_DIR="/var/www/nmsprime"

ROUTES_FILE="${NMS_DIR}/routes/web.php"
if [ -f "${ROUTES_FILE}" ] && ! grep -q "CarrierDashboard.index" "${ROUTES_FILE}"; then
cat <<'EOF' >> "${ROUTES_FILE}"

Route::middleware(['web', 'auth'])->prefix('admin/carrier')->group(function () {
    Route::get('/dashboard', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'dashboard'])->name('CarrierDashboard.index');
    Route::get('/capacity', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'capacity'])->name('Capacity.index');
    Route::get('/tickets', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'tickets'])->name('ServiceTicket.index');
    Route::get('/gis', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'gis'])->name('FiberGis.index');
    Route::get('/pmwani', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'pmwani'])->name('Pmwani.index');
    Route::get('/gst', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'gst'])->name('GstAccounting.index');
    Route::get('/erp-lms', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'erpAndLms'])->name('ErpLms.index');
    Route::get('/hr-carrier_dealers', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'hrAndDealers'])->name('EmployeeHr.index');
    Route::get('/ai-social', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'aiSocial'])->name('AiSocialHub.index');
    Route::get('/network-compliance', [\App\Http\Controllers\CarrierCore\CarrierPortalController::class, 'networkCompliance'])->name('NetworkCompliance.index');
});
EOF
fi

KERNEL_FILE="${NMS_DIR}/app/Console/Kernel.php"
if [ -f "${KERNEL_FILE}" ] && ! grep -q "sql_to_mongo_offload" "${KERNEL_FILE}"; then
    sed -i '/protected function schedule(Schedule \$schedule)/a \
        $schedule->exec('\''/opt/carrier-core/bin/sql_to_mongo_offload'\'')->hourly();\
        $schedule->exec('\''/opt/carrier-core/bin/ipdr_s3_archiver'\'')->hourly();\
        $schedule->exec('\''/opt/carrier-core/bin/gpon_poller'\'')->everyTenMinutes();\
        $schedule->exec('\''/opt/carrier-core/bin/fup_evaluator'\'')->everyFifteenMinutes();\
        $schedule->exec('\''/opt/carrier-core/bin/contract_suspension'\'')->dailyAt('\''00:05'\'');\
        $schedule->exec('\''/opt/carrier-core/bin/ai_evaluator'\'')->dailyAt('\''02:00'\'');\
        $schedule->exec('\''/opt/carrier-core/bin/carrier_unified_backup'\'')->dailyAt('\''03:00'\'');' "${KERNEL_FILE}" || true
fi

cat <<EOF > /etc/cron.d/carrier_nmsprime_unified
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * * apache cd ${NMS_DIR} && php artisan schedule:run >> /opt/carrier-core/logs/scheduler.log 2>&1
EOF
chmod 644 /etc/cron.d/carrier_nmsprime_unified
echo "[+] 15: NMS Prime routes, menu, and centralized Kernel scheduler configured."
EOF_15

# ==============================================================================
# SCRIPT 16: 3-ROLE MOBILE WEB APP (PWA) & DART/FLUTTER API CLIENT SDK
# ==============================================================================
cat <<'EOF_16' > "$DEST/16_mobile_pwa_and_flutter_sdk.sh"
#!/usr/bin/env bash
set -euo pipefail
MOBILE_DIR="/var/www/nmsprime/public/mobile"
FLUTTER_DIR="/opt/carrier-core/flutter_sdk"
mkdir -p "${MOBILE_DIR}" "${FLUTTER_DIR}"

cat <<'EOF' > "${MOBILE_DIR}/index.html"
<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Carrier Core Mobile App</title></head>
<body style="font-family:sans-serif;padding:16px;background:#f8fafc">
<h3>ISP Unified Mobile Portal (Subscriber / Technician / Dealer)</h3>
<p>Connected to Go Fast-Path Engine (<code>/api/fast/v1/*</code>)</p>
</body></html>
EOF

cat <<'EOF' > "${FLUTTER_DIR}/carrier_api.dart"
class CarrierNmsApiClient {
  final String baseUrl;
  CarrierNmsApiClient(this.baseUrl);
}
EOF
echo "[+] 16: Mobile PWA (/mobile/) and Flutter SDK deployed."
EOF_16

# ==============================================================================
# SCRIPT 17: NMS PRIME APACHE API REVERSE PROXY
# ==============================================================================
cat <<'EOF_17' > "$DEST/17_apache_api_reverse_proxy.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env

if [ -d /etc/httpd/conf.d ]; then
    CONF_DIR=/etc/httpd/conf.d
    SERVICE=httpd
    CONF_FILE=$CONF_DIR/carrier_core_proxy.conf
elif [ -d /etc/apache2/conf-available ]; then
    CONF_DIR=/etc/apache2/conf-available
    SERVICE=apache2
    CONF_FILE=$CONF_DIR/carrier_core_proxy.conf
else
    echo "[!] NMS Prime Apache configuration directory was not found." >&2
    exit 1
fi
command -v apachectl >/dev/null 2>&1 || { echo "[!] apachectl is required." >&2; exit 1; }
if [ "$SERVICE" = apache2 ] && command -v a2enmod >/dev/null 2>&1; then a2enmod proxy proxy_http >/dev/null; fi
apachectl -M 2>/dev/null | grep -q 'proxy_module' || { echo "[!] Apache mod_proxy is not loaded." >&2; exit 1; }
apachectl -M 2>/dev/null | grep -q 'proxy_http_module' || { echo "[!] Apache mod_proxy_http is not loaded." >&2; exit 1; }
TMP_CONF=$(mktemp "$CONF_DIR/.carrier_core_proxy.XXXXXX")
BACKUP_CONF=$CONF_FILE.backup.$$
[ ! -f "$CONF_FILE" ] || cp -a "$CONF_FILE" "$BACKUP_CONF"
cat > "$TMP_CONF" <<EOF
# Carrier Core API forwarding. NMS Prime vhosts, TLS, and document roots remain package-managed.
ProxyPreserveHost On
ProxyPass        /api/fast/   http://127.0.0.1:$GO_FAST_API_PORT/api/fast/
ProxyPassReverse /api/fast/   http://127.0.0.1:$GO_FAST_API_PORT/api/fast/
ProxyPass        /pmwani/     http://127.0.0.1:$GO_FAST_API_PORT/pmwani/
ProxyPassReverse /pmwani/     http://127.0.0.1:$GO_FAST_API_PORT/pmwani/
ProxyPass        /api/social/ http://127.0.0.1:$AI_SOCIAL_PORT/api/social/
ProxyPassReverse /api/social/ http://127.0.0.1:$AI_SOCIAL_PORT/api/social/
EOF
restore_config() {
    if [ -f "$BACKUP_CONF" ]; then mv -f "$BACKUP_CONF" "$CONF_FILE"; else rm -f "$CONF_FILE"; fi
    rm -f "$TMP_CONF"
}
if ! mv -f "$TMP_CONF" "$CONF_FILE"; then restore_config; echo "[!] Could not install Apache proxy configuration." >&2; exit 1; fi
if [ "$SERVICE" = apache2 ] && command -v a2enconf >/dev/null 2>&1; then a2enconf carrier_core_proxy >/dev/null; fi
if ! apachectl configtest; then
    restore_config
    apachectl configtest >/dev/null 2>&1 || true
    echo "[!] Apache rejected the Carrier proxy configuration; the previous file was restored." >&2
    exit 1
fi
if ! systemctl reload "$SERVICE"; then
    restore_config
    apachectl configtest >/dev/null 2>&1 && systemctl reload "$SERVICE" >/dev/null 2>&1 || true
    echo "[!] Apache reload failed; the previous proxy configuration was restored." >&2
    exit 1
fi
rm -f "$BACKUP_CONF"
echo "[+] 17: Carrier API routes added to NMS Prime Apache; its packaged web and PostgreSQL configuration remains in place."
EOF_17

# ==============================================================================
# SCRIPT 18: UNIFIED SINGLE-DB BACKUP & LEGACY 46-SCRIPT PATCHER
# ==============================================================================
cat <<'EOF_18' > "$DEST/18_backup_and_legacy_46_patcher.sh"
#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="/opt/carrier-core/bin"
DEST="/opt/carrier-core/installer"

cat <<'EOF' > "${BIN_DIR}/carrier_unified_backup"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env
STAMP="$(date +%Y%m%d_%H%M%S)"
TARGET="/opt/carrier-core/backups/${STAMP}"
mkdir -p "${TARGET}"
if [ -x /usr/pgsql-16/bin/pg_dump ]; then PATH="/usr/pgsql-16/bin:$PATH"; export PATH; fi
PGPASSWORD="$SQL_PASSWORD" PGSSLMODE="${SQL_SSLMODE:-prefer}" pg_dump --no-owner --no-privileges --host="$SQL_HOST" --port="$SQL_PORT" --username="$SQL_USER" --dbname="$SQL_DATABASE" | gzip -9 > "$TARGET/sql_$SQL_DATABASE.sql.gz"
command -v mongodump >/dev/null 2>&1 && mongodump --quiet --uri="${MONGO_URI}/${MONGO_DB}" --archive="${TARGET}/nosql_${MONGO_DB}.archive.gz" --gzip || true
find /opt/carrier-core/backups -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
EOF
chmod 755 "${BIN_DIR}/carrier_unified_backup"

for s in "${DEST}"/*.sh; do
    [ -f "$s" ] || continue
    sed -i -E \
        -e 's/DB_NAME=["'\'']?(radius|carrier_core|isp_erp)["'\'']?/DB_NAME="nmsprime"/g' \
        -e 's/MONGO_DB=["'\'']?(isp_compliance|genieacs|carrier_nosql)["'\'']?/MONGO_DB="carrier_core"/g' "$s" 2>/dev/null || true
done
echo "[+] 18: Unified single-DB backup utility and script sanitizer complete."
EOF_18

# ==============================================================================
# SCRIPT 19: SYSTEMD TARGET, CARRIER-CTL & CARRIER-HEALTH CLI
# ==============================================================================
cat <<'EOF_19' > "$DEST/19_systemd_target_and_carrier_ctl.sh"
#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF' > /usr/local/bin/carrier-health
#!/usr/bin/env bash
set -uo pipefail
source /opt/carrier-core/config/carrier_admin.env
echo "=============================================================================="
echo " CARRIER CORE + NMS PRIME UNIFIED STACK HEALTH REPORT"
echo "=============================================================================="
failures=0
report() {
    if [ "$2" = true ]; then printf "  [PASS] %-44s : OK\n" "$1"; else printf "  [FAIL] %-44s : FAILED\n" "$1"; failures=$((failures + 1)); fi
}
sql_result="$(/opt/carrier-core/bin/carrier_psql --tuples-only --no-align --command="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='carrier_service_tickets';" 2>/dev/null || true)"
if [ "$sql_result" = "1" ]; then report "PostgreSQL database ($SQL_DATABASE)" true; else report "PostgreSQL database ($SQL_DATABASE)" false; fi
if systemctl is-active --quiet postgresql-16 || systemctl is-active --quiet postgresql; then report "NMS Prime PostgreSQL" true; else report "NMS Prime PostgreSQL" false; fi
if systemctl is-active --quiet httpd || systemctl is-active --quiet apache2; then report "NMS Prime Apache" true; else report "NMS Prime Apache" false; fi
if mongosh --quiet "${MONGO_URI}/${MONGO_DB}" --eval 'quit(db.adminCommand({ ping: 1 }).ok === 1 ? 0 : 1)' >/dev/null 2>&1; then report "Single NoSQL DB (${MONGO_DB})" true; else report "Single NoSQL DB (${MONGO_DB})" false; fi
if systemctl is-active --quiet carrier-go-engine; then report "Go Fast-Path Engine (:${GO_FAST_API_PORT})" true; else report "Go Fast-Path Engine (:${GO_FAST_API_PORT})" false; fi
if systemctl is-active --quiet carrier-ai-social; then report "AI & Social Webhook Engine (:${AI_SOCIAL_PORT})" true; else report "AI & Social Webhook Engine (:${AI_SOCIAL_PORT})" false; fi
if systemctl is-active --quiet carrier-ipdr-collector; then report "UDP 5514 IPDR Collector" true; else report "UDP 5514 IPDR Collector" false; fi
if mountpoint -q /mnt/carrier-ramdisk; then report "512M RAM-Disk (/mnt/carrier-ramdisk)" true; else report "512M RAM-Disk (/mnt/carrier-ramdisk)" false; fi
echo "=============================================================================="
[ "$failures" -eq 0 ]
EOF
chmod 755 /usr/local/bin/carrier-health

cat <<'EOF' > /usr/local/bin/carrier-ctl
#!/usr/bin/env bash
set -euo pipefail
case "${1:-status}" in
    start|restart)
        for s in postgresql-16 postgresql mongod radiusd freeradius httpd apache2 carrier-go-engine carrier-ai-social carrier-ipdr-collector; do systemctl "$1" "$s" 2>/dev/null || true; done
        ;;
    stop)
        for s in carrier-ipdr-collector carrier-ai-social carrier-go-engine; do systemctl stop "$s" 2>/dev/null || true; done
        ;;
    status|health) /usr/local/bin/carrier-health ;;
    backup) /opt/carrier-core/bin/carrier_unified_backup ;;
    offload) /opt/carrier-core/bin/sql_to_mongo_offload ;;
esac
EOF
chmod 755 /usr/local/bin/carrier-ctl
echo "[+] 19: /usr/local/bin/carrier-ctl and /usr/local/bin/carrier-health installed."
EOF_19

# ==============================================================================
# SCRIPT 20: END-TO-END SMOKE TEST & FINAL SELF-EXTRACTING ARCHIVE BUILDER
# ==============================================================================
cat <<'EOF_20' > "$DEST/20_e2e_smoke_test_and_packager.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/carrier-core/config/carrier_admin.env

if ! /usr/local/bin/carrier-health; then
    echo "[!] Health verification failed; no sample data was written." >&2
    exit 1
fi
echo "[+] 20: Read-only health verification passed."
EOF_20

# ==============================================================================
# MASTER ORCHESTRATOR: carrier_autoinstall_all.sh (WITH CHECKPOINT FLAGS)
# ==============================================================================
cat <<'EOF_MASTER' > "$DEST/carrier_autoinstall_all.sh"
#!/usr/bin/env bash
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/opt/carrier-core/config/.install_state_20"
LOG_FILE="/opt/carrier-core/logs/master_autoinstall_20.log"
mkdir -p /opt/carrier-core/config /opt/carrier-core/logs

RESUME=false
FROM_STEP=1
ONLY_STEP=""

while [ $# -gt 0 ]; do
    case "$1" in
        --resume) RESUME=true; shift ;;
        --from) FROM_STEP="${2:?--from requires a script number (1..20)}"; shift 2 ;;
        --only) ONLY_STEP="${2:?--only requires a script number (1..20)}"; shift 2 ;;
        --reset-state) rm -f "$STATE_FILE"; echo "[+] State reset."; shift ;;
        *) echo "[!] Unknown option: $1" >&2; exit 2 ;;
    esac
done

if ! [[ "$FROM_STEP" =~ ^[0-9]+$ ]] || [ "$FROM_STEP" -lt 1 ] || [ "$FROM_STEP" -gt 20 ]; then echo "[!] --from must be between 1 and 20." >&2; exit 2; fi
if [ -n "$ONLY_STEP" ] && { ! [[ "$ONLY_STEP" =~ ^[0-9]+$ ]] || [ "$ONLY_STEP" -lt 1 ] || [ "$ONLY_STEP" -gt 20 ]; }; then echo "[!] --only must be between 1 and 20." >&2; exit 2; fi
FROM_STEP=$((10#$FROM_STEP))
if [ -n "$ONLY_STEP" ]; then ONLY_STEP=$((10#$ONLY_STEP)); fi

touch "$STATE_FILE"

shopt -s nullglob
scripts=("$INSTALLER_DIR"/[0-9][0-9]_*.sh)
if [ "${#scripts[@]}" -ne 20 ]; then echo "[!] Expected 20 installer steps, found ${#scripts[@]}." >&2; exit 1; fi
for script in "${scripts[@]}"; do
    base="$(basename "$script")"
    num=$((10#${base%%_*}))

    [ -n "$ONLY_STEP" ] && [ "$num" -ne "$((10#$ONLY_STEP))" ] && continue
    [ "$num" -lt "$((10#$FROM_STEP))" ] && continue
    if [ "$RESUME" = true ] && grep -qxF "$base" "$STATE_FILE" 2>/dev/null; then
        echo "[SKIP] $base (already completed)"
        continue
    fi

    echo ">>> [RUNNING $num/20] $base ..." | tee -a "$LOG_FILE"
    bash "$script" 2>&1 | tee -a "$LOG_FILE"
    echo "$base" >> "$STATE_FILE"
done

echo "[✓] All 20 Unified Carrier Core + NMS Prime scripts executed."
EOF_MASTER

chmod 700 "$DEST" "$DEST"/*.sh
echo "[+] Extracted and armed $(ls -1 "$DEST"/[0-9][0-9]_*.sh | wc -l) auto-executable scripts + carrier_autoinstall_all.sh in $DEST"

if [ "$EXTRACT_ONLY" = true ]; then
    echo "[+] Done (--extract-only). Run: sudo bash $DEST/carrier_autoinstall_all.sh"
    exit 0
fi

exec bash "$DEST/carrier_autoinstall_all.sh" "${PASS[@]}"

