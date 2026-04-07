#!/bin/bash
# export_result.sh — BSM Payment Gateway Health Modeling
# Collects device inventory and Business Service data via API and DB,
# then writes /tmp/bsm_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/bsm_result.json"
TMP_DEVICES_API="/tmp/_bsm_devices_api.json"
TMP_BSM_API="/tmp/_bsm_api.json"
TMP_DEVICES_DB="/tmp/_bsm_devices_db.txt"
TMP_BSM_DB="/tmp/_bsm_db.txt"

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
# 1. Fetch devices from API
# ------------------------------------------------------------
echo "[export] Fetching device list..."
opmanager_api_get "/api/json/device/listDevices" > "$TMP_DEVICES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" \
         > "$TMP_DEVICES_API" 2>/dev/null || \
    echo '{}' > "$TMP_DEVICES_API"

# ------------------------------------------------------------
# 2. Fetch Business Services from API
# ------------------------------------------------------------
echo "[export] Fetching Business Services..."
BSM_FETCHED=0
for endpoint in \
    "/api/json/businessservice/listBusinessServices" \
    "/api/json/bsm/list" \
    "/api/json/itservice/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_BSM_API"
        BSM_FETCHED=1
        echo "[export] Business Services fetched from $endpoint"
        break
    fi
done

if [ "$BSM_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_BSM_API"
    echo "[export] WARNING: Could not fetch Business Services from any endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for Devices and Business Services
# ------------------------------------------------------------
echo "[export] Querying DB for ManagedObjects (Devices & BSMs)..."

{
    echo "=== ManagedObject Nodes (Devices) ==="
    opmanager_query_headers "SELECT name, displayname, ipaddress, type FROM ManagedObject WHERE type='Node' OR type='IpAddress' LIMIT 500;" 2>/dev/null || true
    echo ""
    echo "=== TopoObject (Topology Info) ==="
    opmanager_query_headers "SELECT name, ipaddress FROM TopoObject LIMIT 500;" 2>/dev/null || true
} > "$TMP_DEVICES_DB" 2>&1

{
    echo "=== ManagedObject BusinessServices ==="
    opmanager_query_headers "SELECT name, displayname, type FROM ManagedObject WHERE type='BusinessService' OR type='ITService' LIMIT 100;" 2>/dev/null || true
    echo ""
    echo "=== BusinessService Specific Tables ==="
    
    BSM_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%businessservice%' OR tablename ILIKE '%bsm%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    for tbl in $BSM_TABLES; do
        echo "--- Table: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_BSM_DB" 2>&1


# ------------------------------------------------------------
# 4. Combine into result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

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

devices_api = load_json("/tmp/_bsm_devices_api.json")
bsm_api = load_json("/tmp/_bsm_api.json")
devices_db = load_text("/tmp/_bsm_devices_db.txt")
bsm_db = load_text("/tmp/_bsm_db.txt")

result = {
    "devices_api": devices_api,
    "bsm_api": bsm_api,
    "devices_db_raw": devices_db,
    "bsm_db_raw": bsm_db
}

tmp_out = "/tmp/bsm_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/bsm_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/bsm_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_DEVICES_API" "$TMP_BSM_API" "$TMP_DEVICES_DB" "$TMP_BSM_DB" || true