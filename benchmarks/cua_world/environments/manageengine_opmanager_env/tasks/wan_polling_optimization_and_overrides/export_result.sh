#!/bin/bash
# export_result.sh — WAN Polling Optimization and Overrides
# Collects API and DB configurations for global settings and specific devices.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/wan_polling_result.json"
TMP_SYS_API="/tmp/_sys_api.json"
TMP_DEV1_API="/tmp/_dev1_api.json"
TMP_DEV2_API="/tmp/_dev2_api.json"
TMP_DB_RAW="/tmp/_wan_db_raw.txt"

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
# 2. Fetch configurations from API
# ------------------------------------------------------------
echo "[export] Fetching system settings from API..."
curl -sf "http://localhost:8060/api/json/settings/getSystemSettings?apiKey=${API_KEY}" > "$TMP_SYS_API" 2>/dev/null || echo '{}' > "$TMP_SYS_API"
curl -sf "http://localhost:8060/api/json/admin/getSystemSettings?apiKey=${API_KEY}" >> "$TMP_SYS_API" 2>/dev/null || true

echo "[export] Fetching device details from API..."
curl -sf "http://localhost:8060/api/json/device/getDeviceDetails?apiKey=${API_KEY}&name=Local-Core-SW-01" > "$TMP_DEV1_API" 2>/dev/null || echo '{}' > "$TMP_DEV1_API"
curl -sf "http://localhost:8060/api/json/device/getDeviceDetails?apiKey=${API_KEY}&name=Local-Core-SW-02" > "$TMP_DEV2_API" 2>/dev/null || echo '{}' > "$TMP_DEV2_API"

# ------------------------------------------------------------
# 3. Query DB for comprehensive global parameters and overrides
# ------------------------------------------------------------
echo "[export] Querying PostgreSQL DB for polling parameters..."

# We target tables commonly holding polling intervals and system params
ALL_DB_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%poll%' OR tablename ILIKE '%ping%' OR tablename ILIKE '%param%' OR tablename ILIKE '%setting%' OR tablename ILIKE 'managedobject') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DB POLLING & PARAMS DUMP ==="
    # Ensure some highly likely tables are dumped first
    for exact_tbl in "SystemParams" "GlobalSettings" "PollingDetails" "PolledData" "ManagedObject"; do
        echo "--- TABLE: $exact_tbl ---"
        opmanager_query_headers "SELECT * FROM \"${exact_tbl}\" LIMIT 1000;" 2>/dev/null || true
    done

    # Dump the rest discovered
    for tbl in $ALL_DB_TABLES; do
        if [[ " SystemParams GlobalSettings PollingDetails PolledData ManagedObject " != *" $tbl "* ]]; then
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        fi
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble final result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

def load_json(path):
    try:
        with open(path) as f:
            # Handle concatenated JSON outputs gracefully
            content = f.read().strip()
            if not content: return {}
            # If multiple json objects, split by '}{' and wrap in list
            if '}{' in content:
                content = '[' + content.replace('}{', '},{') + ']'
            return json.loads(content)
    except Exception:
        return {}

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

sys_api = load_json("/tmp/_sys_api.json")
dev1_api = load_json("/tmp/_dev1_api.json")
dev2_api = load_json("/tmp/_dev2_api.json")
db_raw = load_text("/tmp/_wan_db_raw.txt")

result = {
    "system_settings_api": sys_api,
    "device1_api": dev1_api,
    "device2_api": dev2_api,
    "db_raw": db_raw
}

with open("/tmp/wan_polling_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location safely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/wan_polling_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/wan_polling_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Export complete. Output saved to $RESULT_FILE"