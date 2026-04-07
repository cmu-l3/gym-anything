#!/bin/bash
# export_result.sh — Web Application Backup Integrity Monitoring
# Queries the OpManager DB and API for configured file and folder monitors,
# then writes /tmp/backup_monitor_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/backup_monitor_result.json"
TMP_MONITOR_DB="/tmp/_backup_monitor_db.txt"
TMP_MONITOR_API="/tmp/_backup_monitor_api.json"

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
# 1. Query DB for file and folder monitoring profiles
# ------------------------------------------------------------
echo "[export] Querying DB for file/folder monitors..."

# Discover related tables using opmanager_query()
# We look for file, folder, dir, and threshold tables
MONITOR_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%file%' OR tablename ILIKE '%folder%' OR tablename ILIKE '%dir%' OR tablename ILIKE '%thresh%' OR tablename ILIKE '%monitor%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Discovered potential monitor tables: $MONITOR_TABLES"

{
    echo "=== DB MONITOR TABLE RAW EXPORT ==="
    for tbl in $MONITOR_TABLES; do
        # We only want to dump tables that actually sound like they hold the config
        if echo "$tbl" | grep -qEi "(file|folder|dir|thresh|monitor)"; then
            # Avoid dumping massive unrelated tables like 'statsdata' if they caught the 'monitor' filter
            if ! echo "$tbl" | grep -qEi "(stat|perf|log|event|alarm|audit)"; then
                echo ""
                echo "=== TABLE: $tbl ==="
                opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 300;" 2>/dev/null || true
            fi
        fi
    done
} > "$TMP_MONITOR_DB" 2>&1

# ------------------------------------------------------------
# 2. Query OpManager API for localhost monitors
# ------------------------------------------------------------
echo "[export] Querying OpManager API for localhost device monitors..."
# Try both localhost and 127.0.0.1
API_RESP_1=$(curl -sf "http://localhost:8060/api/json/device/getMonitors?apiKey=${API_KEY}&deviceName=localhost" 2>/dev/null || echo '{}')
API_RESP_2=$(curl -sf "http://localhost:8060/api/json/device/getMonitors?apiKey=${API_KEY}&deviceName=127.0.0.1" 2>/dev/null || echo '{}')

# Combine them into a single array-like structure
echo "{\"localhost\": ${API_RESP_1}, \"127_0_0_1\": ${API_RESP_2}}" > "$TMP_MONITOR_API"

# ------------------------------------------------------------
# 3. Assemble result JSON
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

db_raw = load_text("/tmp/_backup_monitor_db.txt")
api_data = load_json("/tmp/_backup_monitor_api.json")

result = {
    "monitor_db_raw": db_raw,
    "monitor_api": api_data
}

tmp_out = "/tmp/backup_monitor_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Ensure safe write/move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/backup_monitor_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/backup_monitor_result_tmp.json" "$RESULT_FILE" 2>/dev/null || sudo mv "/tmp/backup_monitor_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_MONITOR_DB" "$TMP_MONITOR_API" || true