#!/bin/bash
# export_result.sh — Healthcare IoT Device Template Configuration
# Collects configuration data from the API and DB, then writes /tmp/healthcare_iot_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/healthcare_iot_result.json"
TMP_SERVICES_API="/tmp/_services_api.json"
TMP_TEMPLATES_API="/tmp/_templates_api.json"
TMP_DB_DUMP="/tmp/_db_dump.txt"

# ------------------------------------------------------------
# Obtain API key
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# 1. Fetch via API
# ------------------------------------------------------------
echo "[export] Fetching Services from API..."
curl -sf "http://localhost:8060/api/json/admin/getServices?apiKey=${API_KEY}" > "$TMP_SERVICES_API" 2>/dev/null || echo '{}' > "$TMP_SERVICES_API"

echo "[export] Fetching Device Templates from API..."
curl -sf "http://localhost:8060/api/json/deviceTemplate/listDeviceTemplates?apiKey=${API_KEY}" > "$TMP_TEMPLATES_API" 2>/dev/null || echo '{}' > "$TMP_TEMPLATES_API"

# ------------------------------------------------------------
# 2. Query DB for Service and Template tables
# ------------------------------------------------------------
echo "[export] Querying DB for configuration data..."

TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%template%' OR tablename ILIKE '%sysoid%' OR tablename ILIKE '%service%' OR tablename ILIKE '%port%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' || true)

{
    echo "=== DATABASE DUMP ==="
    for tbl in $TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > "$TMP_DB_DUMP" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

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

result = {
    "services_api": load_json("/tmp/_services_api.json"),
    "templates_api": load_json("/tmp/_templates_api.json"),
    "db_raw": load_text("/tmp/_db_dump.txt")
}

with open("/tmp/healthcare_iot_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/healthcare_iot_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/healthcare_iot_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

rm -f "$TMP_SERVICES_API" "$TMP_TEMPLATES_API" "$TMP_DB_DUMP" || true