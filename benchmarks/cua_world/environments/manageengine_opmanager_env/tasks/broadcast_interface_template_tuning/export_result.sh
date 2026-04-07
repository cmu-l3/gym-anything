#!/bin/bash
# export_result.sh — Broadcast Interface Template Tuning
# Queries API and DB for interface templates and threshold configurations.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/interface_tuning_result.json"
TMP_TEMPLATES_API="/tmp/_interface_templates_api.json"
TMP_TEMPLATES_DB="/tmp/_interface_templates_db.txt"

# Obtain API key
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
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

# 1. Fetch interface templates from API
echo "[export] Fetching interface templates from API..."
API_FETCHED=0

for endpoint in \
    "/api/json/admin/getInterfaceTemplates" \
    "/api/json/admin/interfaceTemplates" \
    "/api/json/interface/listTemplates"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_TEMPLATES_API"
        API_FETCHED=1
        echo "[export] Interface templates fetched from $endpoint"
        break
    fi
done

if [ "$API_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_TEMPLATES_API"
fi

# 2. Query DB for Interface Templates and Thresholds
echo "[export] Querying DB for interface templates..."

ALL_IF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%interfacetemplate%' OR tablename ILIKE '%threshold%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== INTERFACE TEMPLATES & THRESHOLD TABLES ==="
    for tbl in $ALL_IF_TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > "$TMP_TEMPLATES_DB" 2>&1

# 3. Assemble result JSON
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return {}

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except:
        return ""

api_data = load_json("/tmp/_interface_templates_api.json")
db_data = load_text("/tmp/_interface_templates_db.txt")

result = {
    "interface_templates_api": api_data,
    "interface_templates_db_raw": db_data
}

with open("/tmp/interface_tuning_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/interface_tuning_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/interface_tuning_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_TEMPLATES_API" "$TMP_TEMPLATES_DB" || true