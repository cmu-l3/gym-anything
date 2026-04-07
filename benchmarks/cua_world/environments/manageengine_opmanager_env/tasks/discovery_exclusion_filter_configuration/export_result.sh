#!/bin/bash
# export_result.sh — Discovery Exclusion Filter Configuration
# Collects exclusion settings via DB query and API, writes to JSON.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/discovery_exclusion_result.json"
TMP_EXC_DB="/tmp/_discovery_exc_db.txt"
TMP_EXC_API="/tmp/_discovery_exc_api.json"

echo "[export] === Exporting Discovery Exclusion Filters ==="

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
# 2. Query DB for Exclusion Tables
# ------------------------------------------------------------
echo "[export] Querying DB for ignore/exclude tables..."

# Find all tables with ignore, exclude, filter, or discover in their names
EXC_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%ignore%' OR tablename ILIKE '%exclude%' OR tablename ILIKE '%filter%' OR tablename ILIKE '%mac%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Potential exclusion tables discovered: $EXC_TABLES"

{
    echo "=== EXCLUSION TABLE SEARCH RESULTS ==="
    echo "All candidate tables: $EXC_TABLES"
    echo ""

    if [ -n "$EXC_TABLES" ]; then
        for tbl in $EXC_TABLES; do
            echo "=== TABLE: $tbl ==="
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
            echo ""
        done
    else
        echo "NO_EXCLUSION_TABLES_FOUND"
    fi
} > "$TMP_EXC_DB" 2>&1

# ------------------------------------------------------------
# 3. Query Exclusion APIs (Fallback)
# ------------------------------------------------------------
echo "[export] Fetching exclusion lists via API..."

# OpManager API endpoints for ignored lists (if exposed)
API_DATA="{}"
for endpoint in \
    "/api/json/discovery/getIgnoredIPs" \
    "/api/json/discovery/getIgnoredMACs" \
    "/api/json/admin/getIgnoredMACs" \
    "/api/json/admin/getIgnoredIPs"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | grep -qi "ignore\|mac\|ip\|success"; then
        API_DATA=$(python3 -c "import json; d1=json.loads('''$API_DATA'''); d2=json.loads('''$RESP'''); d1['$endpoint']=d2; print(json.dumps(d1))" 2>/dev/null || echo "$API_DATA")
    fi
done

echo "$API_DATA" > "$TMP_EXC_API"

# ------------------------------------------------------------
# 4. Assemble Result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, sys

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

db_raw = load_text("/tmp/_discovery_exc_db.txt")
api_raw = load_json("/tmp/_discovery_exc_api.json")

result = {
    "exclusion_db_raw": db_raw,
    "exclusion_api_data": api_raw
}

with open("/tmp/discovery_exclusion_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move securely to final destination
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/discovery_exclusion_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/discovery_exclusion_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_EXC_DB" "$TMP_EXC_API" "/tmp/discovery_exclusion_result_tmp.json" || true

echo "[export] === Export Complete ==="