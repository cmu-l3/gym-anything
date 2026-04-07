#!/bin/bash
# export_result.sh — Process Health Monitors Config
# Collects API and DB data for devices and process monitors, exporting to JSON.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/process_health_result.json"
TMP_DEVICES_API="/tmp/_proc_devices_api.json"
TMP_PROC_API="/tmp/_proc_monitors_api.json"
TMP_FINAL_DB="/tmp/_final_process_db.txt"
TMP_SNMP="/tmp/_snmp_processes.txt"
TMP_INIT_DB="/tmp/initial_process_db.txt"

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
# 2. Fetch Devices from API
# ------------------------------------------------------------
echo "[export] Fetching device list..."
opmanager_api_get "/api/json/device/listDevices" > "$TMP_DEVICES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" \
         > "$TMP_DEVICES_API" 2>/dev/null || \
    echo '{}' > "$TMP_DEVICES_API"

# ------------------------------------------------------------
# 3. Fetch Process Monitors from API (Try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching process monitors from API..."
PROC_FETCHED=0

for endpoint in \
    "/api/json/process/listProcessMonitors" \
    "/api/json/monitor/listProcessMonitors" \
    "/api/json/device/getAssociatedMonitors"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" >> "$TMP_PROC_API"
        PROC_FETCHED=1
    fi
done

if [ "$PROC_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_PROC_API"
fi

# ------------------------------------------------------------
# 4. Capture Final Database State
# ------------------------------------------------------------
echo "[export] Querying DB for final process monitor tables..."

PROC_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%process%' OR tablename ILIKE '%monitor%' OR tablename ILIKE '%resource%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

> "$TMP_FINAL_DB"
for tbl in $PROC_TABLES; do
    echo "=== TABLE: $tbl ===" >> "$TMP_FINAL_DB"
    opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null >> "$TMP_FINAL_DB" || true
done

# ------------------------------------------------------------
# 5. Execute SNMP Walk for running processes (Verification Evidence)
# ------------------------------------------------------------
echo "[export] Executing SNMP walk to verify running processes..."
snmpwalk -v2c -c public 127.0.0.1 1.3.6.1.2.1.25.4.2.1.2 > "$TMP_SNMP" 2>/dev/null || echo "SNMP_FAILED" > "$TMP_SNMP"

# ------------------------------------------------------------
# 6. Combine into result JSON
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

devices_api = load_json("/tmp/_proc_devices_api.json")
proc_api = load_text("/tmp/_proc_monitors_api.json")
init_db_raw = load_text("/tmp/initial_process_db.txt")
final_db_raw = load_text("/tmp/_final_process_db.txt")
snmp_raw = load_text("/tmp/_snmp_processes.txt")

result = {
    "devices_api": devices_api,
    "process_monitors_api_raw": proc_api,
    "initial_db_raw": init_db_raw,
    "final_db_raw": final_db_raw,
    "snmp_walk_raw": snmp_raw
}

tmp_out = "/tmp/process_health_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Safely write the final JSON file
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/process_health_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/process_health_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

# Take final screenshot
take_screenshot "/tmp/process_monitors_final_screenshot.png" || true

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_DEVICES_API" "$TMP_PROC_API" "$TMP_FINAL_DB" "$TMP_SNMP" || true