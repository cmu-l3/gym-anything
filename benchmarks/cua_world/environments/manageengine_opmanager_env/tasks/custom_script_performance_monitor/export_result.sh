#!/bin/bash
# export_result.sh — Custom Script Performance Monitor
# Collects credential, script template, and device monitor data.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/custom_script_monitor_result.json"
TMP_CREDS_API="/tmp/_scriptmon_creds_api.json"
TMP_DEV_MON_API="/tmp/_scriptmon_dev_api.json"
TMP_DB_RAW="/tmp/_scriptmon_db.txt"

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
# 1. Fetch Credentials from API
# ------------------------------------------------------------
echo "[export] Fetching credentials via API..."
opmanager_api_get "/api/json/admin/getCredentials" > "$TMP_CREDS_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/admin/getCredentials?apiKey=${API_KEY}" > "$TMP_CREDS_API" 2>/dev/null || \
    echo '{}' > "$TMP_CREDS_API"

# ------------------------------------------------------------
# 2. Fetch Device Monitors for 127.0.0.1
# ------------------------------------------------------------
echo "[export] Fetching device monitors for localhost..."
# First, try to resolve the Device ID for 127.0.0.1
DEV_ID=""
DEV_RESP=$(curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" 2>/dev/null || true)
if [ -n "$DEV_RESP" ]; then
    DEV_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    devices = data.get('data', data.get('devices', []))
    for d in devices:
        if d.get('name') == '127.0.0.1' or d.get('ipAddress') == '127.0.0.1':
            print(d.get('name', ''))
            break
except Exception:
    pass
" "$DEV_RESP" 2>/dev/null || true)
fi

TARGET_DEV="${DEV_ID:-127.0.0.1}"
opmanager_api_get "/api/json/device/getMonitors?deviceName=${TARGET_DEV}" > "$TMP_DEV_MON_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/getMonitors?deviceName=${TARGET_DEV}&apiKey=${API_KEY}" > "$TMP_DEV_MON_API" 2>/dev/null || \
    echo '{}' > "$TMP_DEV_MON_API"

# ------------------------------------------------------------
# 3. Comprehensive DB Query (Schema-Agnostic)
# ------------------------------------------------------------
echo "[export] Querying DB for script templates and credentials..."

# Fetch all tables containing 'script', 'template', 'cred', 'threshold', or 'monitor'
ALL_RELEVANT_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%script%' OR tablename ILIKE '%cred%' OR tablename ILIKE '%template%' OR tablename ILIKE '%threshold%' OR tablename ILIKE '%monitor%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DB SEARCH RESULTS ==="
    echo "Tables scanned: $ALL_RELEVANT_TABLES"
    for tbl in $ALL_RELEVANT_TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble Result JSON
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

creds_api = load_json("/tmp/_scriptmon_creds_api.json")
dev_mon_api = load_json("/tmp/_scriptmon_dev_api.json")
db_raw = load_text("/tmp/_scriptmon_db.txt")

result = {
    "credentials_api": creds_api,
    "device_monitors_api": dev_mon_api,
    "db_raw": db_raw
}

with open("/tmp/custom_script_monitor_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "[export] Result written to $RESULT_FILE"

# Clean up temporary files
rm -f "$TMP_CREDS_API" "$TMP_DEV_MON_API" "$TMP_DB_RAW" || true