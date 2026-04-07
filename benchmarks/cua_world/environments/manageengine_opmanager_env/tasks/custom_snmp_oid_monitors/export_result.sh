#!/bin/bash
# export_result.sh — Custom SNMP Monitor Configuration
# Collects custom monitor data via API and DB, then writes /tmp/custom_snmp_monitors_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/custom_snmp_monitors_result.json"
TMP_MONITORS_API="/tmp/_monitors_api.json"
TMP_MONITORS_DB="/tmp/_monitors_db.txt"

# 1. Obtain API key
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

# 2. Fetch monitors via API
echo "[export] Fetching custom monitors via API..."
MONITORS_FETCHED=0

for endpoint in \
    "/api/json/monitor/listMonitors" \
    "/api/json/snmp/getCustomMonitors" \
    "/api/json/device/getMonitorList" \
    "/api/json/device/getMonitors"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_MONITORS_API"
        MONITORS_FETCHED=1
        echo "[export] Monitors fetched from $endpoint"
        break
    fi
done

if [ "$MONITORS_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_MONITORS_API"
    echo "[export] WARNING: Could not fetch monitors from API." >&2
fi

# 3. Query DB for monitor/OID data
echo "[export] Querying DB for monitor and OID tables..."

ALL_MONITOR_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%monitor%' OR tablename ILIKE '%polleddata%' OR tablename ILIKE '%graph%' OR tablename ILIKE '%custom%' OR tablename ILIKE '%oid%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== MONITOR TABLE SEARCH RESULTS ==="
    echo "Candidate tables: $ALL_MONITOR_TABLES"
    echo ""

    TABLE_COUNT=0
    for tbl in $ALL_MONITOR_TABLES; do
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 15 ]; then
            break # limit dumps to prevent massive files
        fi
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
        echo ""
    done
} > "$TMP_MONITORS_DB" 2>&1

# 4. Take final screenshot
take_screenshot "/tmp/custom_monitor_final_screenshot.png" || true

# 5. Assemble result JSON
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

monitors_api = load_json("/tmp/_monitors_api.json")
monitors_db_raw = load_text("/tmp/_monitors_db.txt")

result = {
    "monitors_api": monitors_api,
    "monitors_db_raw": monitors_db_raw
}

tmp_out = "/tmp/custom_snmp_monitors_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/custom_snmp_monitors_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/custom_snmp_monitors_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_MONITORS_API" "$TMP_MONITORS_DB" || true