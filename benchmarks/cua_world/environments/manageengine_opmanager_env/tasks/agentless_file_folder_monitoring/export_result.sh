#!/bin/bash
# export_result.sh — Agentless File and Folder Monitoring
# Collects credential profiles, assigned device credentials, and file/folder monitors.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/agentless_file_folder_result.json"

TMP_API_CREDS="/tmp/_api_creds.json"
TMP_API_DEVICE="/tmp/_api_device.json"
TMP_API_MONITORS="/tmp/_api_monitors.json"

TMP_DB_CREDS="/tmp/_db_creds.txt"
TMP_DB_MONITORS="/tmp/_db_monitors.txt"

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
echo "[export] API key present: $([ -n "$API_KEY" ] && echo yes || echo no)"

# ------------------------------------------------------------
# 2. Fetch data via API
# ------------------------------------------------------------
echo "[export] Fetching Credentials via API..."
curl -sf "http://localhost:8060/api/json/credential/listCredentials?apiKey=${API_KEY}" 2>/dev/null > "$TMP_API_CREDS" || echo '{}' > "$TMP_API_CREDS"

echo "[export] Fetching Device info via API (127.0.0.1)..."
curl -sf "http://localhost:8060/api/json/device/getDevice?name=127.0.0.1&apiKey=${API_KEY}" 2>/dev/null > "$TMP_API_DEVICE" || echo '{}' > "$TMP_API_DEVICE"

echo "[export] Fetching Device Monitors via API (127.0.0.1)..."
curl -sf "http://localhost:8060/api/json/device/getMonitors?deviceName=127.0.0.1&apiKey=${API_KEY}" 2>/dev/null > "$TMP_API_MONITORS" || echo '{}' > "$TMP_API_MONITORS"

# ------------------------------------------------------------
# 3. Query DB for Credentials and Monitors
# ------------------------------------------------------------
echo "[export] Querying DB for credentials and monitors..."

{
    echo "=== CREDENTIAL TABLES ==="
    ALL_CRED_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%cred%' OR tablename ILIKE '%cli%' OR tablename ILIKE '%ssh%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' || true)
    for tbl in $ALL_CRED_TABLES; do
        echo "--- Table: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_DB_CREDS"

{
    echo "=== FILE/FOLDER MONITOR TABLES ==="
    ALL_MON_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%filemon%' OR tablename ILIKE '%dirmon%' OR tablename ILIKE '%foldermon%' OR tablename ILIKE '%agentless%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' || true)
    for tbl in $ALL_MON_TABLES; do
        echo "--- Table: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done
} > "$TMP_DB_MONITORS"

# ------------------------------------------------------------
# 4. Take final screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/agentless_final_screenshot.png" || true

# ------------------------------------------------------------
# 5. Assemble Result JSON
# ------------------------------------------------------------
echo "[export] Assembling final result JSON..."

python3 << 'PYEOF'
import json, sys

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

result = {
    "api_credentials": load_json("/tmp/_api_creds.json"),
    "api_device": load_json("/tmp/_api_device.json"),
    "api_monitors": load_json("/tmp/_api_monitors.json"),
    "db_credentials_raw": load_text("/tmp/_db_creds.txt"),
    "db_monitors_raw": load_text("/tmp/_db_monitors.txt")
}

with open("/tmp/agentless_file_folder_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "[export] Export complete. Output saved to $RESULT_FILE"