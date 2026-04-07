#!/bin/bash
# export_result.sh — OT ICS Device Taxonomy Provisioning
# Collects configuration data from OpManager's DB and API to verify taxonomy changes.

set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "[export] === Exporting OT ICS Device Taxonomy Results ==="

RESULT_FILE="/tmp/ot_ics_result.json"
TMP_DB_RAW="/tmp/_ot_db_raw.txt"
TMP_API_RAW="/tmp/_ot_api_raw.json"

# Record end time and take final screenshot
date +%s > /tmp/task_end_time.txt
take_screenshot "/tmp/ot_ics_final_screenshot.png" || true

# ------------------------------------------------------------
# 1. Obtain API key for REST calls
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    echo "[export] API key not found; attempting local login..." >&2
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
# 2. Query OpManager API for taxonomy data
# ------------------------------------------------------------
echo "[export] Querying API for categories, vendors, and templates..."
{
    echo "=== API CATEGORIES ==="
    curl -sf "http://localhost:8060/api/json/admin/getDeviceCategories?apiKey=${API_KEY}" 2>/dev/null || echo "{}"
    echo "=== API VENDORS ==="
    curl -sf "http://localhost:8060/api/json/deviceTemplate/getVendors?apiKey=${API_KEY}" 2>/dev/null || echo "{}"
    echo "=== API TEMPLATES ==="
    # This endpoint might paginate or require different params, but we do a best-effort fetch
    curl -sf "http://localhost:8060/api/json/deviceTemplate/getTemplates?apiKey=${API_KEY}" 2>/dev/null || echo "{}"
} > "$TMP_API_RAW" || true

# ------------------------------------------------------------
# 3. Query PostgreSQL DB for taxonomy tables
# ------------------------------------------------------------
echo "[export] Querying DB for taxonomy tables..."
# Discover tables related to categories, vendors, templates, and OIDs.
# We exclude event/audit/managedobject tables to keep the dump focused.
TAXONOMY_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%vendor%' OR tablename ILIKE '%category%' OR tablename ILIKE '%template%' OR tablename ILIKE '%sysoid%' OR tablename ILIKE '%devicetype%') AND tablename NOT ILIKE '%managedobject%' AND tablename NOT ILIKE '%event%' AND tablename NOT ILIKE '%audit%' ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Target tables: $TAXONOMY_TABLES"

{
    echo "=== DB TAXONOMY DUMP ==="
    for tbl in $TAXONOMY_TABLES; do
        if [ -n "$tbl" ]; then
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
        fi
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble Result JSON
# ------------------------------------------------------------
echo "[export] Assembling final result JSON..."

python3 << 'PYEOF'
import json, sys, os

def read_file(path):
    try:
        with open(path, 'r') as f:
            return f.read()
    except Exception:
        return ""

api_raw = read_file("/tmp/_ot_api_raw.json")
db_raw = read_file("/tmp/_ot_db_raw.txt")

result = {
    "api_dump": api_raw,
    "db_dump": db_raw,
    "screenshot_exists": os.path.exists("/tmp/ot_ics_final_screenshot.png")
}

tmp_out = "/tmp/ot_ics_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location safely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/ot_ics_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/ot_ics_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

# Cleanup
rm -f "$TMP_DB_RAW" "$TMP_API_RAW" 2>/dev/null || true

echo "[export] === Export Complete. Data saved to $RESULT_FILE ==="