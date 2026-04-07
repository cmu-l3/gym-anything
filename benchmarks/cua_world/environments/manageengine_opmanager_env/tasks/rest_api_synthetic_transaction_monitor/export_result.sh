#!/bin/bash
# export_result.sh — REST API Synthetic Transaction Monitor
# Collects URL monitor data from the API and DB, captures the mock API logs,
# and writes everything to /tmp/api_monitor_result.json.

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/api_monitor_result.json"
TMP_MONITORS_API="/tmp/_api_monitors.json"
TMP_MONITORS_DB="/tmp/_db_raw.txt"

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
# 2. Fetch URL monitors from API (try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching URL monitors from API..."
URL_MON_FETCHED=0

for endpoint in \
    "/api/json/url/getURLMonitorList" \
    "/api/json/webmon/listWebMonitors" \
    "/api/json/webmonitor/listWebMonitors" \
    "/api/json/url/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_MONITORS_API"
        URL_MON_FETCHED=1
        echo "[export] URL monitors fetched from $endpoint"
        break
    fi
done

if [ "$URL_MON_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_MONITORS_API"
    echo "[export] WARNING: Could not fetch URL monitors from any API endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for URL / web monitor data
# ------------------------------------------------------------
echo "[export] Querying DB for URL monitor tables..."

# Enumerate all monitor-related tables
ALL_MONITOR_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%web%' OR tablename ILIKE '%url%' OR tablename ILIKE '%monitor%' OR tablename ILIKE '%http%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Discovered tables: $ALL_MONITOR_TABLES"

{
    echo "=== MONITOR TABLE SEARCH RESULTS ==="
    for tbl in $ALL_MONITOR_TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_MONITORS_DB" 2>&1

# ------------------------------------------------------------
# 4. Take final screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/api_monitor_final_screenshot.png" || true

# ------------------------------------------------------------
# 5. Assemble result JSON cleanly via Python
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, sys, os

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

monitors_api = load_json("/tmp/_api_monitors.json")
monitors_db_raw = load_text("/tmp/_db_raw.txt")
mock_log = load_text("/tmp/mock_api_requests.log")

result = {
    "monitors_api": monitors_api,
    "monitors_db_raw": monitors_db_raw,
    "mock_api_log": mock_log
}

tmp_out = "/tmp/api_monitor_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/api_monitor_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/api_monitor_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_MONITORS_API" "$TMP_MONITORS_DB" || true