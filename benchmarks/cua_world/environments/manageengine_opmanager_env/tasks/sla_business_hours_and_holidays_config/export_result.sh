#!/bin/bash
# export_result.sh — SLA Business Hours and Holidays Config
# Queries the OpManager DB and API for business hours and holiday profiles,
# then writes the output to /tmp/sla_calendar_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/sla_calendar_result.json"
TMP_SLA_DB="/tmp/_sla_db.txt"
TMP_SLA_API="/tmp/_sla_api.json"

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
# 1. Query DB for Business Hours and Holidays
# ------------------------------------------------------------
echo "[export] Querying DB for business hours and holidays..."

# Discover relevant tables
ALL_SLA_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%business%' OR tablename ILIKE '%holiday%' OR tablename ILIKE '%time%window%' OR tablename ILIKE '%sla%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Relevant SLA tables: $ALL_SLA_TABLES"

{
    echo "=== SLA DB TABLE SEARCH RESULTS ==="
    echo "Tables found: $ALL_SLA_TABLES"
    echo ""

    if [ -z "$ALL_SLA_TABLES" ]; then
        echo "NO_SLA_TABLES_FOUND"
    else
        for tbl in $ALL_SLA_TABLES; do
            echo ""
            echo "=== TABLE: $tbl ==="
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        done
    fi
} > "$TMP_SLA_DB" 2>&1

# ------------------------------------------------------------
# 2. Query API for business hours/holidays (Fallback)
# ------------------------------------------------------------
echo "[export] Querying API for SLA profiles..."
API_JSON="{}"
for endpoint in \
    "/api/json/admin/getBusinessHours" \
    "/api/json/admin/getHolidays" \
    "/api/json/settings/businessHours"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        # Merge JSON responses heuristically
        API_JSON=$(python3 -c "
import json, sys
try:
    current = json.loads('$API_JSON')
    new_data = json.loads(sys.argv[1])
    current.update(new_data)
    print(json.dumps(current))
except Exception:
    print('$API_JSON')
" "$RESP")
    fi
done
echo "$API_JSON" > "$TMP_SLA_API"

# ------------------------------------------------------------
# 3. Assemble result JSON
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

sla_db  = load_text("/tmp/_sla_db.txt")
sla_api = load_json("/tmp/_sla_api.json")

result = {
    "sla_db_raw": sla_db,
    "sla_api_raw": sla_api
}

tmp_out = "/tmp/sla_calendar_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Safely copy to the final destination
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/sla_calendar_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/sla_calendar_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_SLA_DB" "$TMP_SLA_API" || true