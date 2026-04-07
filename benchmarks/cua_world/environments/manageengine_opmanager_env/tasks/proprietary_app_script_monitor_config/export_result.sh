#!/bin/bash
# export_result.sh — Proprietary App Script Monitor Config
# Collects API and Database data about Credentials, Scripts, and Thresholds.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/script_monitor_result.json"
TMP_CRED_API="/tmp/_sm_cred_api.json"
TMP_MONITOR_API="/tmp/_sm_monitor_api.json"
TMP_DB_DUMP="/tmp/_sm_db_dump.txt"

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
# 2. Fetch data from API
# ------------------------------------------------------------
echo "[export] Fetching APIs..."

# Fetch credentials (often accessible via /api/json/admin/getCredentials or similar, 
# but we try general endpoints just in case)
curl -sf "http://localhost:8060/api/json/credential/listCredentials?apiKey=${API_KEY}" > "$TMP_CRED_API" 2>/dev/null || echo '{}' > "$TMP_CRED_API"

# Fetch monitors for localhost (127.0.0.1)
curl -sf "http://localhost:8060/api/json/device/getMonitors?apiKey=${API_KEY}&name=127.0.0.1" > "$TMP_MONITOR_API" 2>/dev/null || echo '{}' > "$TMP_MONITOR_API"

# ------------------------------------------------------------
# 3. Query DB for Credentials, Scripts, and Thresholds
# ------------------------------------------------------------
echo "[export] Querying Database for relevant tables..."

# Find all tables related to credentials, scripts, and thresholds
TARGET_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%cred%' OR tablename ILIKE '%script%' OR tablename ILIKE '%thresh%' OR tablename ILIKE '%monitor%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DB SEARCH RESULTS ==="
    echo "Tables targeted: $TARGET_TABLES"
    echo ""

    for tbl in $TARGET_TABLES; do
        # We only dump tables that likely contain our targets to avoid massive files
        if echo "$tbl" | grep -qiE "credential|script|threshold|polleddata|monitortemplate"; then
            echo "=== TABLE: $tbl ==="
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
            echo ""
        fi
    done
} > "$TMP_DB_DUMP" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
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

cred_api = load_json("/tmp/_sm_cred_api.json")
monitor_api = load_json("/tmp/_sm_monitor_api.json")
db_raw = load_text("/tmp/_sm_db_dump.txt")

result = {
    "credentials_api": cred_api,
    "monitors_api": monitor_api,
    "db_raw": db_raw
}

tmp_out = "/tmp/_sm_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/_sm_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/_sm_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_CRED_API" "$TMP_MONITOR_API" "$TMP_DB_DUMP" "/tmp/_sm_result_tmp.json" || true