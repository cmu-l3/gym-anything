#!/bin/bash
# export_result.sh — Endpoint Security Baseline Template Setup
# Collects device templates and windows services data from the API and DB,
# then writes /tmp/endpoint_security_result.json.

set -euo pipefail
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/endpoint_security_result.json"
TMP_SERVICES_API="/tmp/_services_api.json"
TMP_TEMPLATES_API="/tmp/_templates_api.json"
TMP_DB_RAW="/tmp/_endpoint_security_db.txt"

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
# 1. Fetch Windows Services from API
# ------------------------------------------------------------
echo "[export] Fetching Windows Services via API..."
opmanager_api_get "/api/json/windowsService/listWindowsServices" > "$TMP_SERVICES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/windowsService/listWindowsServices?apiKey=${API_KEY}" \
         > "$TMP_SERVICES_API" 2>/dev/null || \
    echo '{}' > "$TMP_SERVICES_API"

# ------------------------------------------------------------
# 2. Fetch Device Templates from API
# ------------------------------------------------------------
echo "[export] Fetching Device Templates via API..."
opmanager_api_get "/api/json/deviceTemplate/listDeviceTemplates" > "$TMP_TEMPLATES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/deviceTemplate/listDeviceTemplates?apiKey=${API_KEY}" \
         > "$TMP_TEMPLATES_API" 2>/dev/null || \
    echo '{}' > "$TMP_TEMPLATES_API"

# ------------------------------------------------------------
# 3. Query DB for Services and Templates
# ------------------------------------------------------------
echo "[export] Querying DB for relevant tables..."

# Find all tables containing 'service', 'win', 'template'
CANDIDATE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%service%' OR tablename ILIKE '%win%' OR tablename ILIKE '%template%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DB TABLE DUMP ==="
    for tbl in $CANDIDATE_TABLES; do
        echo "--- TABLE: $tbl ---"
        # Dump limited records to avoid massive files, but ensure we catch new additions
        # Often new additions are at the end, so order by first column descending if possible, or just dump 500
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, sys

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

services_api = load_json("/tmp/_services_api.json")
templates_api = load_json("/tmp/_templates_api.json")
db_raw = load_text("/tmp/_endpoint_security_db.txt")

result = {
    "windows_services_api": services_api,
    "device_templates_api": templates_api,
    "db_raw_dump": db_raw
}

out_file = "/tmp/endpoint_security_result_tmp.json"
with open(out_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {out_file}")
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/endpoint_security_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/endpoint_security_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_SERVICES_API" "$TMP_TEMPLATES_API" "$TMP_DB_RAW" || true