#!/bin/bash
# export_result.sh — Datacenter Device Onboarding
# Collects device list from the API and direct DB queries,
# then outputs a JSON payload for the verifier.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/dc2_onboarding_result.json"
TMP_DEVICES_API="/tmp/_dc2_devices_api.json"
TMP_DEVICES_DB="/tmp/_dc2_devices_db.txt"

echo "[export] === Exporting Datacenter Device Onboarding Results ==="

# Take final screenshot
take_screenshot "/tmp/dc2_onboarding_final_screenshot.png" || true

# ------------------------------------------------------------
# 1. Obtain API key
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
# 2. Fetch Devices via API
# ------------------------------------------------------------
echo "[export] Fetching device list via API..."
opmanager_api_get "/api/json/device/listDevices" > "$TMP_DEVICES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" \
         > "$TMP_DEVICES_API" 2>/dev/null || \
    echo '{}' > "$TMP_DEVICES_API"

# ------------------------------------------------------------
# 3. Fetch Devices via DB Query
# ------------------------------------------------------------
echo "[export] Querying DB for device tables..."

# Find possible device tables (ManagedObject, TopoObject, NetworkInfo, etc.)
ALL_DEVICE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%device%' OR tablename ILIKE '%managed%' OR tablename ILIKE '%topo%' OR tablename ILIKE '%network%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DEVICE TABLE SEARCH RESULTS ==="
    echo "Candidate tables: $ALL_DEVICE_TABLES"
    echo ""

    # Dump the top 5 most relevant tables
    TABLE_COUNT=0
    for tbl in $ALL_DEVICE_TABLES; do
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 5 ]; then
            break
        fi
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > "$TMP_DEVICES_DB" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, sys

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

devices_api = load_json("/tmp/_dc2_devices_api.json")
devices_db  = load_text("/tmp/_dc2_devices_db.txt")

result = {
    "devices_api": devices_api,
    "devices_db_raw": devices_db
}

tmp_out = "/tmp/dc2_onboarding_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move securely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/dc2_onboarding_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/dc2_onboarding_result_tmp.json" "$RESULT_FILE"
    chmod 644 "$RESULT_FILE"
fi

echo "[export] Results exported successfully to $RESULT_FILE"

# Cleanup temps
rm -f "$TMP_DEVICES_API" "$TMP_DEVICES_DB" || true