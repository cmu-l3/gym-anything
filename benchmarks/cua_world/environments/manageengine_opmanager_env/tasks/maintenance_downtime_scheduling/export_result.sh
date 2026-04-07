#!/bin/bash
# export_result.sh — Maintenance Downtime Scheduling
# Collects scheduled downtime data via API and DB, then writes /tmp/maintenance_downtime_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/maintenance_downtime_result.json"
TMP_DT_API="/tmp/_dt_schedule_api.json"
TMP_DT_DB="/tmp/_dt_schedule_db.txt"

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
echo "[export] API key present: $([ -n "$API_KEY" ] && echo yes || echo no)"

# ------------------------------------------------------------
# 2. Fetch downtime schedules via API (try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching downtime schedules via API..."
DT_FETCHED=0

for endpoint in \
    "/api/json/admin/getDowntimeSchedulers" \
    "/api/json/admin/listDowntimeSchedules" \
    "/api/json/maintenance/list" \
    "/api/json/downtime/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_DT_API"
        DT_FETCHED=1
        echo "[export] Downtime schedules fetched from $endpoint"
        break
    fi
done

if [ "$DT_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_DT_API"
    echo "[export] WARNING: Could not fetch downtime schedules from any API endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for downtime scheduler tables
# ------------------------------------------------------------
echo "[export] Querying DB for downtime scheduler tables..."

# Discover downtime/maintenance related table names
DT_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%downtime%' OR tablename ILIKE '%maintenance%' OR tablename ILIKE '%dtschedule%' OR tablename ILIKE 'task%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

echo "[export] Primary downtime table discovered: '${DT_TABLE}'"

# Collect all matching table names
ALL_DT_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%downtime%' OR tablename ILIKE '%maintenance%' OR tablename ILIKE '%schedule%' OR tablename ILIKE 'task%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
echo "[export] All relevant tables: $ALL_DT_TABLES"

{
    if [ -n "$DT_TABLE" ]; then
        echo "=== PRIMARY TABLE: $DT_TABLE ==="
        opmanager_query_headers "SELECT * FROM \"${DT_TABLE}\" LIMIT 200;" 2>/dev/null || true
    else
        echo "NO_DOWNTIME_TABLE_FOUND"
    fi

    # Query additional downtime tables to ensure we capture the data
    TABLE_COUNT=0
    for tbl in $ALL_DT_TABLES; do
        if [ "$tbl" = "$DT_TABLE" ]; then
            continue
        fi
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 6 ]; then
            break
        fi
        echo ""
        echo "=== SECONDARY TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 150;" 2>/dev/null || true
    done
} > "$TMP_DT_DB" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
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

dt_db  = load_text("/tmp/_dt_schedule_db.txt")
dt_api = load_json("/tmp/_dt_schedule_api.json")

result = {
    "downtime_schedules_db_raw": dt_db,
    "downtime_schedules_api": dt_api,
    "export_timestamp": os.popen("date -u +'%Y-%m-%dT%H:%M:%SZ'").read().strip()
}

tmp_out = "/tmp/maintenance_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure safe write permissions
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/maintenance_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/maintenance_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Final screenshot
take_screenshot "/tmp/maintenance_downtime_final_screenshot.png" || true

# Cleanup temp files
rm -f "$TMP_DT_DB" "$TMP_DT_API" "/tmp/maintenance_result_tmp.json" || true