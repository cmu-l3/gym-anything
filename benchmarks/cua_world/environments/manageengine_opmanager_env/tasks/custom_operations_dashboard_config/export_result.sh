#!/bin/bash
# export_result.sh — Custom Operations Dashboard Configuration
# Collects dashboard and widget data via API and DB, then writes /tmp/dashboard_config_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/dashboard_config_result.json"
TMP_API_RESP="/tmp/_dashboards_api.json"
TMP_DB_RAW="/tmp/_dashboards_db.txt"

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
# 2. Fetch dashboards via API
# ------------------------------------------------------------
echo "[export] Fetching dashboards via API..."
API_FETCHED=0

for endpoint in \
    "/api/json/dashboard/getDashboards" \
    "/api/json/v2/dashboards" \
    "/api/json/customview/getCustomViews"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    
    # Verify it's valid JSON
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_API_RESP"
        API_FETCHED=1
        echo "[export] Dashboards fetched from $endpoint"
        break
    fi
done

if [ "$API_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_API_RESP"
    echo "[export] WARNING: Could not fetch dashboard list from any API endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for dashboard and widget tables
# ------------------------------------------------------------
echo "[export] Querying DB for dashboard/view/widget data..."

# Enumerate all relevant tables
ALL_DASHBOARD_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%dashboard%' OR tablename ILIKE '%widget%' OR tablename ILIKE '%customview%' OR tablename ILIKE '%userview%' OR tablename ILIKE '%layout%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Target tables: $ALL_DASHBOARD_TABLES"

{
    echo "=== DASHBOARD & WIDGET TABLES ==="
    # Dump each table (limit rows to avoid massive files)
    TABLE_COUNT=0
    for tbl in $ALL_DASHBOARD_TABLES; do
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 25 ]; then
            break # Safety limit
        fi
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble Result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, os

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

api_data = load_json("/tmp/_dashboards_api.json")
db_raw   = load_text("/tmp/_dashboards_db.txt")

result = {
    "dashboards_api": api_data,
    "dashboards_db_raw": db_raw
}

tmp_out = "/tmp/dashboard_config_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move to final destination
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/dashboard_config_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/dashboard_config_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Clean up
rm -f "$TMP_API_RESP" "$TMP_DB_RAW" "/tmp/dashboard_config_result_tmp.json" || true