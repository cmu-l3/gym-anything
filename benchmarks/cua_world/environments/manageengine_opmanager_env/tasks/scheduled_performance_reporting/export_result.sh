#!/bin/bash
# export_result.sh — Scheduled Performance Reporting
# Collects scheduled report data via API and DB, then writes /tmp/reporting_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/reporting_result.json"
TMP_REPORTS_API="/tmp/_reporting_api.json"
TMP_SCHEDULED_API="/tmp/_reporting_scheduled_api.json"
TMP_REPORT_DB="/tmp/_reporting_db.txt"
TMP_SCHEDULE_DB="/tmp/_reporting_schedule_db.txt"

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
# 2. Fetch scheduled reports via API (try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching report list via API..."
REPORTS_FETCHED=0

for endpoint in \
    "/api/json/report/listReports" \
    "/api/json/reports/listReports" \
    "/api/json/report/list" \
    "/api/json/reports/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_REPORTS_API"
        REPORTS_FETCHED=1
        echo "[export] Report list fetched from $endpoint"
        break
    fi
done

if [ "$REPORTS_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_REPORTS_API"
    echo "[export] WARNING: Could not fetch report list from any list endpoint." >&2
fi

echo "[export] Fetching scheduled reports via API..."
SCHEDULED_FETCHED=0

for endpoint in \
    "/api/json/reports/getScheduledReports" \
    "/api/json/report/getScheduledReports" \
    "/api/json/report/scheduledReports" \
    "/api/json/reports/scheduledReports"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_SCHEDULED_API"
        SCHEDULED_FETCHED=1
        echo "[export] Scheduled reports fetched from $endpoint"
        break
    fi
done

if [ "$SCHEDULED_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_SCHEDULED_API"
    echo "[export] WARNING: Could not fetch scheduled reports from any endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for report and schedule tables
# ------------------------------------------------------------
echo "[export] Querying DB for report/schedule data..."

# Discover report-related table names using opmanager_query()
REPORT_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%report%' OR tablename ILIKE '%schedule%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

echo "[export] Primary report/schedule table discovered: '${REPORT_TABLE}'"

# Also collect all matching table names for diagnostics
ALL_REPORT_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%report%' OR tablename ILIKE '%schedule%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
echo "[export] All report/schedule tables: $ALL_REPORT_TABLES"

{
    # Query the first matching table
    if [ -n "$REPORT_TABLE" ]; then
        echo "=== PRIMARY TABLE: $REPORT_TABLE ==="
        opmanager_query_headers "SELECT * FROM \"${REPORT_TABLE}\" LIMIT 200;" 2>/dev/null || true
    else
        echo "NO_REPORT_TABLE_FOUND"
    fi

    # Query additional report/schedule tables
    for tbl in $ALL_REPORT_TABLES; do
        if [ "$tbl" = "$REPORT_TABLE" ]; then
            continue
        fi
        echo ""
        echo "=== SECONDARY TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done

    # Search tables with email/recipient columns
    echo ""
    echo "=== EMAIL/RECIPIENT COLUMN TABLES ==="
    EMAIL_SEARCH=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN (SELECT table_name FROM information_schema.columns WHERE table_schema='public' AND (column_name ILIKE '%email%' OR column_name ILIKE '%mail%' OR column_name ILIKE '%recipient%')) ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    echo "Tables with email columns: $EMAIL_SEARCH"
    for tbl in $EMAIL_SEARCH; do
        echo ""
        echo "=== EMAIL TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_REPORT_DB" 2>&1

echo "" > "$TMP_SCHEDULE_DB" 2>/dev/null || true

# ------------------------------------------------------------
# 4. Combine into result JSON
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

reports_api      = load_json("/tmp/_reporting_api.json")
scheduled_api    = load_json("/tmp/_reporting_scheduled_api.json")
report_db_raw    = load_text("/tmp/_reporting_db.txt")
schedule_db_raw  = load_text("/tmp/_reporting_schedule_db.txt")

result = {
    "reports_api":           reports_api,
    "scheduled_reports_api": scheduled_api,
    "report_db_raw":         report_db_raw,
    "schedule_db_raw":       schedule_db_raw,
}

tmp_out = "/tmp/reporting_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe_write_json if available, otherwise direct move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/reporting_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/reporting_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_REPORTS_API" "$TMP_SCHEDULED_API" "$TMP_REPORT_DB" "$TMP_SCHEDULE_DB" || true
