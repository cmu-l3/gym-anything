#!/bin/bash
# export_result.sh — CMDB Asset Metadata Integration
# Collects device templates, custom fields, and device properties for 127.0.0.1
# then writes /tmp/cmdb_integration_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/cmdb_integration_result.json"

TMP_TEMPLATES_DB="/tmp/_cmdb_templates_db.txt"
TMP_CUSTOMFIELDS_DB="/tmp/_cmdb_customfields_db.txt"
TMP_DEVICE_PROPS_DB="/tmp/_cmdb_device_props_db.txt"
TMP_DEVICE_API="/tmp/_cmdb_device_api.json"

# ------------------------------------------------------------
# Obtain API key
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    echo "[export] API key not found; attempting login..." >&2
    LOGIN_RESP=$(curl -sf -X POST \
        "http://localhost:8060/apiv2/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=Admin%40123" 2>/dev/null || true)
    if [ -n "$LOGIN_RESP" ]; then
        API_KEY=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))
except Exception:
    pass
" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

# ------------------------------------------------------------
# 1. API: Fetch 127.0.0.1 Device Details
# ------------------------------------------------------------
echo "[export] Fetching 127.0.0.1 device details from API..."

# Resolve device list to find 127.0.0.1
DEVICE_LIST_RESP=$(opmanager_api_get "/api/json/device/listDevices" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" 2>/dev/null || echo '{}')

DEVICE_NAME_RESOLVED=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    devices = data if isinstance(data, list) else data.get('data', data.get('devices', data.get('deviceList', [])))
    if not isinstance(devices, list):
        devices = []
    for d in devices:
        if isinstance(d, dict):
            ip = d.get('ipAddress', d.get('ip', d.get('name', '')))
            name = d.get('displayName', d.get('name', ''))
            if ip == '127.0.0.1' or name == '127.0.0.1':
                print(name)
                sys.exit(0)
    print('127.0.0.1')
except Exception:
    print('127.0.0.1')
" "$DEVICE_LIST_RESP" 2>/dev/null || echo "127.0.0.1")

DEVICE_DETAILS_RESP=$(opmanager_api_get "/api/json/device/getDeviceDetails?name=${DEVICE_NAME_RESOLVED}" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/getDeviceDetails?apiKey=${API_KEY}&name=${DEVICE_NAME_RESOLVED}" 2>/dev/null || echo '{}')
echo "$DEVICE_DETAILS_RESP" > "$TMP_DEVICE_API"


# ------------------------------------------------------------
# 2. DB: Query Templates, Custom Fields, Device Properties
# ------------------------------------------------------------
echo "[export] Querying DB for metadata and device details..."

# Device Templates
TEMPLATE_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%devicetemplate%' ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
if [ -z "$TEMPLATE_TABLE" ]; then
    TEMPLATE_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%typedefinition%' ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
fi

if [ -n "$TEMPLATE_TABLE" ]; then
    opmanager_query_headers "SELECT * FROM \"${TEMPLATE_TABLE}\" LIMIT 500;" 2>/dev/null > "$TMP_TEMPLATES_DB" || echo "QUERY_FAILED" > "$TMP_TEMPLATES_DB"
else
    echo "NO_TEMPLATE_TABLE_FOUND" > "$TMP_TEMPLATES_DB"
fi

# Custom Fields definitions
CF_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%customfield%' OR tablename ILIKE '%userfield%') AND tablename NOT ILIKE '%value%' ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

if [ -n "$CF_TABLE" ]; then
    opmanager_query_headers "SELECT * FROM \"${CF_TABLE}\" LIMIT 500;" 2>/dev/null > "$TMP_CUSTOMFIELDS_DB" || echo "QUERY_FAILED" > "$TMP_CUSTOMFIELDS_DB"
else
    echo "NO_CUSTOMFIELD_TABLE_FOUND" > "$TMP_CUSTOMFIELDS_DB"
fi

# Try all custom field / user field tables to ensure values are captured
ALL_CF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%customfield%' OR tablename ILIKE '%userfield%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
{
    echo "=== ALL CUSTOM/USER FIELD TABLES ==="
    for tbl in $ALL_CF_TABLES; do
        echo "--- $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} >> "$TMP_CUSTOMFIELDS_DB"

# Device Properties (ManagedObject, etc) to link 127.0.0.1 to fields
MO_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE 'managedobject' ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

{
    echo "=== MANAGED OBJECT ==="
    if [ -n "$MO_TABLE" ]; then
        # Check specifically for the localhost device
        opmanager_query_headers "SELECT * FROM \"${MO_TABLE}\" WHERE name='127.0.0.1' OR ipaddress='127.0.0.1';" 2>/dev/null || true
    fi
} > "$TMP_DEVICE_PROPS_DB"

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, os

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

device_api = load_json("/tmp/_cmdb_device_api.json")
templates_db = load_text("/tmp/_cmdb_templates_db.txt")
customfields_db = load_text("/tmp/_cmdb_customfields_db.txt")
device_props_db = load_text("/tmp/_cmdb_device_props_db.txt")

result = {
    "device_api": device_api,
    "templates_db_raw": templates_db,
    "customfields_db_raw": customfields_db,
    "device_props_db_raw": device_props_db
}

tmp_out = "/tmp/cmdb_integration_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/cmdb_integration_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/cmdb_integration_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_TEMPLATES_DB" "$TMP_CUSTOMFIELDS_DB" "$TMP_DEVICE_PROPS_DB" "$TMP_DEVICE_API" "/tmp/cmdb_integration_result_tmp.json" || true