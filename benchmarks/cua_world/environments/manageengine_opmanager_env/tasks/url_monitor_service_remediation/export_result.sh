#!/bin/bash
# export_result.sh — URL Monitor Service Remediation
# Collects URL monitor data from the API and DB,
# then writes /tmp/url_monitor_result.json.

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/url_monitor_result.json"
TMP_MONITORS_API="/tmp/_urlmon_api.json"
TMP_MONITORS_DB="/tmp/_urlmon_db.txt"

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
# 1. Fetch URL monitors from API (try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching URL monitors from API..."
URL_MON_FETCHED=0

for endpoint in \
    "/api/json/url/getURLMonitorList" \
    "/api/json/webmon/listWebMonitors" \
    "/api/json/webmonitor/listWebMonitors"; do
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
# 2. Query DB for URL / web monitor data
# ------------------------------------------------------------
echo "[export] Querying DB for URL monitor tables..."

# Discover URL/web monitor related table using opmanager_query()
URL_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%web%' OR tablename ILIKE '%url%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

if [ -z "$URL_TABLE" ]; then
    URL_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%monitor%' ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
fi

# Enumerate all monitor-related tables
ALL_MONITOR_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%web%' OR tablename ILIKE '%url%' OR tablename ILIKE '%monitor%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] All monitor-related tables: $ALL_MONITOR_TABLES"

{
    echo "=== MONITOR TABLE SEARCH RESULTS ==="
    echo "Tables found: $ALL_MONITOR_TABLES"
    echo ""

    if [ -n "$URL_TABLE" ]; then
        echo "=== PRIMARY TABLE: $URL_TABLE ==="
        opmanager_query_headers "SELECT * FROM \"${URL_TABLE}\" LIMIT 500;" 2>/dev/null || true
    else
        echo "NO_URL_MONITOR_TABLE_FOUND"
    fi

    # Dump each additional discovered table (up to 3)
    TABLE_COUNT=0
    for tbl in $ALL_MONITOR_TABLES; do
        if [ "$tbl" = "$URL_TABLE" ]; then
            continue
        fi
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 3 ]; then
            break
        fi
        echo ""
        echo "=== ADDITIONAL TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done
} > /tmp/_urlmon_db_combined.txt 2>&1

# Also write primary table to TMP_MONITORS_DB for legacy reference
if [ -n "$URL_TABLE" ]; then
    opmanager_query "SELECT * FROM \"${URL_TABLE}\" LIMIT 500;" 2>/dev/null > "$TMP_MONITORS_DB" || echo "QUERY_FAILED" > "$TMP_MONITORS_DB"
else
    echo "NO_URL_MONITOR_TABLE_FOUND" > "$TMP_MONITORS_DB"
fi

# ------------------------------------------------------------
# 3. Combine into result JSON
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

monitors_api = load_json("/tmp/_urlmon_api.json")
monitors_db_raw = load_text("/tmp/_urlmon_db_combined.txt")

result = {
    "url_monitors_api": monitors_api,
    "url_monitors_db_raw": monitors_db_raw,
}

tmp_out = "/tmp/url_monitor_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe_write_json if available, otherwise direct move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/url_monitor_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/url_monitor_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_MONITORS_API" "$TMP_MONITORS_DB" /tmp/_urlmon_db_combined.txt || true
