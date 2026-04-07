#!/bin/bash
# export_result.sh — SNMP Trap Processor Config

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/trap_processor_result.json"
TMP_TRAP_API="/tmp/_trap_api.json"
TMP_TRAP_DB="/tmp/_trap_db.txt"

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
# 1. Fetch trap processors via API
# ------------------------------------------------------------
echo "[export] Fetching trap processors via API..."
TRAP_API_RESP=$(opmanager_api_get "/api/json/trap/listTrapProcessors" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/trap/listTrapProcessors?apiKey=${API_KEY}" 2>/dev/null || \
    echo '{}')
    
# Fallback to alternate endpoint if empty
if [ -z "$TRAP_API_RESP" ] || [ "$TRAP_API_RESP" = "null" ]; then
    TRAP_API_RESP=$(opmanager_api_get "/api/json/admin/snmpTrapProcessors" 2>/dev/null || echo '{}')
fi

echo "$TRAP_API_RESP" > "$TMP_TRAP_API"

# ------------------------------------------------------------
# 2. Query DB for trap processor tables
# ------------------------------------------------------------
echo "[export] Querying DB for trap processor tables..."

# Find all potential trap/processor tables
TRAP_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%trap%' OR tablename ILIKE '%processor%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== TRAP/PROCESSOR TABLES ==="
    echo "Tables found: $TRAP_TABLES"
    echo ""

    # Dump the contents of these tables
    for tbl in $TRAP_TABLES; do
        if [ -n "$tbl" ]; then
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
            echo ""
        fi
    done
} > "$TMP_TRAP_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble JSON Result
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

trap_api = load_json("/tmp/_trap_api.json")
trap_db = load_text("/tmp/_trap_db.txt")

result = {
    "trap_processors_api": trap_api,
    "trap_processors_db_raw": trap_db
}

with open("/tmp/trap_processor_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/trap_processor_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/trap_processor_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

# Cleanup
rm -f "$TMP_TRAP_API" "$TMP_TRAP_DB" "/tmp/trap_processor_result_tmp.json" || true

echo "[export] Result written to $RESULT_FILE"