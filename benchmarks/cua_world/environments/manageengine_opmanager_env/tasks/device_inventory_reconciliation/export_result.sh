#!/bin/bash
# export_result.sh — Device Inventory Reconciliation
# Collects device details via OpManager REST API and DB queries to verify changes.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/device_inventory_result.json"
TMP_DEVICES_API="/tmp/_inv_devices_api.json"
TMP_TARGETS_API="/tmp/_inv_targets_api.txt"
TMP_DB_DUMP="/tmp/_inv_db_dump.txt"

# ------------------------------------------------------------
# 1. Take Final Screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/inventory_final_screenshot.png" || true

# ------------------------------------------------------------
# 2. Obtain API key
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
# 3. Fetch Full Device List via API
# ------------------------------------------------------------
echo "[export] Fetching device list via API..."
opmanager_api_get "/api/json/device/listDevices" > "$TMP_DEVICES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" \
         > "$TMP_DEVICES_API" 2>/dev/null || \
    echo '{}' > "$TMP_DEVICES_API"

# ------------------------------------------------------------
# 4. Fetch Details for Target Devices specifically via API
# ------------------------------------------------------------
echo "[export] Fetching detailed device properties via API..."
> "$TMP_TARGETS_API"
for dev in "Core-Switch-HQ-01" "App-Server-Prod-01" "Perimeter-FW-DMZ-01" "UNKNOWN-DEVICE-01"; do
    RESP=$(curl -sf "http://localhost:8060/api/json/device/getDeviceDetails?apiKey=${API_KEY}&deviceName=${dev}" 2>/dev/null || true)
    if [ -n "$RESP" ]; then
        echo "=== TARGET: $dev ===" >> "$TMP_TARGETS_API"
        echo "$RESP" >> "$TMP_TARGETS_API"
        echo "" >> "$TMP_TARGETS_API"
    fi
done

# ------------------------------------------------------------
# 5. Query PostgreSQL DB for all related device tables
# ------------------------------------------------------------
echo "[export] Querying PostgreSQL for raw database state..."
{
    echo "=== TABLE: managedobject ==="
    opmanager_query_headers "SELECT * FROM managedobject;" 2>/dev/null || true
    echo ""
    echo "=== TABLE: toponode ==="
    opmanager_query_headers "SELECT * FROM toponode;" 2>/dev/null || true
    echo ""
    echo "=== TABLE: systeminfo ==="
    opmanager_query_headers "SELECT * FROM systeminfo;" 2>/dev/null || true
    echo ""
    echo "=== TABLE: deviceproperties ==="
    opmanager_query_headers "SELECT * FROM deviceproperties;" 2>/dev/null || true
    echo ""
    echo "=== TABLE: customproperties ==="
    # Some versions store user-added fields in customproperties
    opmanager_query_headers "SELECT * FROM customproperties;" 2>/dev/null || true
} > "$TMP_DB_DUMP" 2>&1

# ------------------------------------------------------------
# 6. Read Task Start Timestamps
# ------------------------------------------------------------
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_device_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(opmanager_query "SELECT count(*) FROM managedobject WHERE type='Node';" 2>/dev/null || echo "0")

# ------------------------------------------------------------
# 7. Assemble Result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << PYEOF
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

devices_api = load_json("${TMP_DEVICES_API}")
targets_api_raw = load_text("${TMP_TARGETS_API}")
db_dump_raw = load_text("${TMP_DB_DUMP}")

result = {
    "task_start_timestamp": ${TASK_START},
    "initial_device_count": ${INITIAL_COUNT},
    "current_device_count": ${CURRENT_COUNT},
    "devices_api": devices_api,
    "targets_api_raw": targets_api_raw,
    "db_dump_raw": db_dump_raw,
    "screenshot_exists": os.path.exists("/tmp/inventory_final_screenshot.png")
}

tmp_out = "/tmp/device_inventory_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/device_inventory_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/device_inventory_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_DEVICES_API" "$TMP_TARGETS_API" "$TMP_DB_DUMP" || true
echo "[export] Export complete."