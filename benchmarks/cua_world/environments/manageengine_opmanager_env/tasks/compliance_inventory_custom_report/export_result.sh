#!/bin/bash
# export_result.sh — Compliance Inventory Custom Report
# Collects custom report configurations from the OpManager API and PostgreSQL database.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/compliance_report_result.json"
TMP_API_JSON="/tmp/_compliance_api.json"
TMP_DB_TXT="/tmp/_compliance_db.txt"

echo "[export] === Exporting Compliance Inventory Custom Report ==="

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
# 2. Fetch Custom Reports via API
# ------------------------------------------------------------
echo "[export] Fetching custom report list via API..."
API_FETCHED=0

for endpoint in \
    "/api/json/report/listCustomReports" \
    "/api/json/reports/customReports" \
    "/api/json/report/listReports" \
    "/api/json/customreport/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_API_JSON"
        API_FETCHED=1
        echo "[export] Report list fetched from $endpoint"
        break
    fi
done

if [ "$API_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_API_JSON"
    echo "[export] WARNING: Could not fetch custom report list via API endpoints." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for Report and Column tables
# ------------------------------------------------------------
echo "[export] Querying DB for report configuration tables..."

# Find all tables related to reports or custom configurations
ALL_REPORT_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%report%' OR tablename ILIKE '%custom%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DISCOVERED REPORT TABLES ==="
    echo "$ALL_REPORT_TABLES"
    echo ""

    for tbl in $ALL_REPORT_TABLES; do
        echo "=== TABLE: $tbl ==="
        # Fetch the most recent 100 entries to catch the newly created report
        # Attempt to order by the first column descending (often an ID), fallback to arbitrary 100
        opmanager_query_headers "SELECT * FROM \"${tbl}\" ORDER BY 1 DESC LIMIT 100;" 2>/dev/null || \
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
        echo ""
    done
} > "$TMP_DB_TXT" 2>&1

echo "[export] Database dump completed."

# ------------------------------------------------------------
# 4. Take final screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/compliance_report_final.png" || true

# ------------------------------------------------------------
# 5. Assemble final JSON
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

result = {
    "api_data": load_json("/tmp/_compliance_api.json"),
    "db_data": load_text("/tmp/_compliance_db.txt")
}

with open("/tmp/compliance_report_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/compliance_report_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/compliance_report_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_API_JSON" "$TMP_DB_TXT" /tmp/compliance_report_result_tmp.json || true
echo "[export] === Export Complete ==="