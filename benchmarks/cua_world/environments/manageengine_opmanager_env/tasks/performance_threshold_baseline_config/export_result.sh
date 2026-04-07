#!/bin/bash
# export_result.sh — Configuring Performance Monitor Thresholds per Baseline Policy
# Queries the OpManager DB and API for threshold data, then writes JSON result.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/performance_threshold_result.json"
TMP_DB_RAW="/tmp/_threshold_db_raw.txt"
TMP_API_RAW="/tmp/_threshold_api_raw.json"

echo "[export] === Exporting Performance Threshold Task Results ==="

# Take final screenshot
take_screenshot "/tmp/task_final_state.png" || true

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
# 2. Query DB for Threshold and Monitor Tables
# ------------------------------------------------------------
echo "[export] Querying database for threshold configurations..."

# Discover threshold-related table names
TABLES_TO_CHECK=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%thresh%' OR tablename ILIKE '%monitor%' OR tablename ILIKE '%perf%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DB THRESHOLD TABLE DUMP ==="
    for tbl in $TABLES_TO_CHECK; do
        # We only dump tables that actually have rows to save space, and focus on those with numbers matching our thresholds
        COUNT=$(opmanager_query "SELECT COUNT(*) FROM \"${tbl}\";" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$COUNT" != "0" ] && [ "$COUNT" -lt 1000 ]; then
            echo ""
            echo "--- TABLE: $tbl ($COUNT rows) ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        fi
    done
} > "$TMP_DB_RAW" 2>&1

echo "[export] Database dump completed."

# ------------------------------------------------------------
# 3. Query API for Monitors
# ------------------------------------------------------------
echo "[export] Querying API for device monitors..."

# Try to fetch device list first to get device IDs
API_DUMP="{}"
DEVICES_JSON=$(curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" 2>/dev/null || echo "{}")

# Store it in our temp dump
echo "$DEVICES_JSON" > "$TMP_API_RAW"

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling final JSON..."

python3 << 'PYEOF'
import json, os

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

db_raw = load_text("/tmp/_threshold_db_raw.txt")
api_raw = load_text("/tmp/_threshold_api_raw.json")
try:
    api_json = json.loads(api_raw)
except Exception:
    api_json = {}

result = {
    "db_dump": db_raw,
    "api_dump": api_json,
    "task_end": os.popen("date +%s").read().strip()
}

with open("/tmp/performance_threshold_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "[export] Results saved to $RESULT_FILE"
echo "[export] === Export Complete ==="