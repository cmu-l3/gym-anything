#!/bin/bash
# export_result.sh — Datacenter Rack Elevation Mapping
# Collects device lists and deeply inspects spatial/rack database tables.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/rack_mapping_result.json"
TMP_DEVICES_API="/tmp/_rack_devices_api.json"
TMP_MO_MAPPING="/tmp/_rack_mo_mapping.txt"
TMP_RACK_DB="/tmp/_rack_db_raw.txt"

# ------------------------------------------------------------
# 1. Obtain API key
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
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
# 2. Fetch Device List from API (To verify discovery)
# ------------------------------------------------------------
echo "[export] Fetching device list from API..."
opmanager_api_get "/api/json/device/listDevices" > "$TMP_DEVICES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" \
         > "$TMP_DEVICES_API" 2>/dev/null || \
    echo '{}' > "$TMP_DEVICES_API"

# ------------------------------------------------------------
# 3. Fetch ManagedObject mappings (IP to ID)
# ------------------------------------------------------------
echo "[export] Querying ManagedObject mappings..."
opmanager_query_headers "SELECT name, ipaddress, id FROM ManagedObject WHERE ipaddress LIKE '127.0.0.%';" > "$TMP_MO_MAPPING" 2>/dev/null || echo "" > "$TMP_MO_MAPPING"

# ------------------------------------------------------------
# 4. Deep search all Rack, Map, Floor, and Cabinet tables
# ------------------------------------------------------------
echo "[export] Searching for Rack and Spatial Mapping tables..."

ALL_RACK_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%rack%' OR tablename ILIKE '%cabinet%' OR tablename ILIKE '%floor%' OR tablename ILIKE '%datacenter%' OR tablename ILIKE '%map%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Identified spatial tables: $ALL_RACK_TABLES"

{
    echo "=== RACK & SPATIAL DB DUMP ==="
    if [ -n "$ALL_RACK_TABLES" ]; then
        for tbl in $ALL_RACK_TABLES; do
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
        done
    else
        echo "NO_RACK_TABLES_FOUND"
    fi
} > "$TMP_RACK_DB" 2>&1

# ------------------------------------------------------------
# 5. Assemble Result JSON
# ------------------------------------------------------------
echo "[export] Assembling JSON result..."

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

devices_api = load_json("/tmp/_rack_devices_api.json")
mo_mapping  = load_text("/tmp/_rack_mo_mapping.txt")
rack_db     = load_text("/tmp/_rack_db_raw.txt")

result = {
    "devices_api": devices_api,
    "mo_mapping": mo_mapping,
    "rack_db_raw": rack_db
}

out_tmp = "/tmp/rack_mapping_result_tmp.json"
with open(out_tmp, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/rack_mapping_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/rack_mapping_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_DEVICES_API" "$TMP_MO_MAPPING" "$TMP_RACK_DB" "/tmp/rack_mapping_result_tmp.json" || true