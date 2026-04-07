#!/bin/bash
# export_result.sh — Data Center Power Infrastructure Monitoring Setup

set -euo pipefail
source /workspace/scripts/task_utils.sh

# Take final screenshot before exporting
take_screenshot "/tmp/task_final_screenshot.png" || true

RESULT_FILE="/tmp/power_infrastructure_result.json"

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
# 1. Fetch via API
# ------------------------------------------------------------
echo "[export] Fetching configuration profiles from API..."
curl -sf "http://localhost:8060/api/json/admin/listCredentials?apiKey=${API_KEY}" > /tmp/_api_creds.json 2>/dev/null || echo "{}" > /tmp/_api_creds.json
curl -sf "http://localhost:8060/api/json/deviceTemplate/listDeviceTemplates?apiKey=${API_KEY}" > /tmp/_api_templates.json 2>/dev/null || echo "{}" > /tmp/_api_templates.json
curl -sf "http://localhost:8060/api/json/notification/listNotificationProfiles?apiKey=${API_KEY}" > /tmp/_api_notifs.json 2>/dev/null || echo "{}" > /tmp/_api_notifs.json

# ------------------------------------------------------------
# 2. Query DB to capture custom monitors and exact strings
# ------------------------------------------------------------
echo "[export] Querying underlying database for exact matches..."
{
    echo "=== CREDENTIAL TABLES ==="
    for tbl in $(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%credential%') LIMIT 5;" 2>/dev/null | tr -d ' \t' || true); do
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done

    echo "=== TEMPLATE TABLES ==="
    for tbl in $(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%template%') LIMIT 5;" 2>/dev/null | tr -d ' \t' || true); do
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done

    echo "=== MONITOR TABLES ==="
    for tbl in $(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%monitor%' OR tablename ILIKE '%graph%') LIMIT 10;" 2>/dev/null | tr -d ' \t' || true); do
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done

    echo "=== NOTIFICATION TABLES ==="
    for tbl in $(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%') LIMIT 5;" 2>/dev/null | tr -d ' \t' || true); do
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > /tmp/_power_db_dump.txt 2>&1

# ------------------------------------------------------------
# 3. Assemble JSON Result
# ------------------------------------------------------------
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

res = {
    "api_credentials": load_json("/tmp/_api_creds.json"),
    "api_templates": load_json("/tmp/_api_templates.json"),
    "api_notifications": load_json("/tmp/_api_notifs.json"),
    "db_dump": load_text("/tmp/_power_db_dump.txt")
}

with open("/tmp/power_infrastructure_result_tmp.json", "w") as f:
    json.dump(res, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/power_infrastructure_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/power_infrastructure_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Export complete. Written to $RESULT_FILE"