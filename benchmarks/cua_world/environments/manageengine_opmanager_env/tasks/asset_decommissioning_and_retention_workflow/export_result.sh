#!/bin/bash
# export_result.sh — Asset Decommissioning and Retention Workflow
# Collects device statuses, group memberships, and raw DB records.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/asset_decommission_result.json"

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

# ------------------------------------------------------------
# 1. Fetch via API
# ------------------------------------------------------------
echo "[export] Fetching data via API..."
opmanager_api_get "/api/json/device/listDevices" > /tmp/api_devices.json 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" > /tmp/api_devices.json 2>/dev/null || \
    echo '{}' > /tmp/api_devices.json

opmanager_api_get "/api/json/group/listGroups" > /tmp/api_groups.json 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" > /tmp/api_groups.json 2>/dev/null || \
    echo '{}' > /tmp/api_groups.json

# ------------------------------------------------------------
# 2. Query DB as primary source of truth
# ------------------------------------------------------------
echo "[export] Querying DB..."
# Extract device names and managed status
opmanager_query "SELECT displayname, managed FROM ManagedObject;" > /tmp/db_managed_objects.txt 2>/dev/null || echo "" > /tmp/db_managed_objects.txt

# Extract group names
opmanager_query "SELECT viewname FROM CustomView;" > /tmp/db_custom_view.txt 2>/dev/null || echo "" > /tmp/db_custom_view.txt

# Extract group memberships (entity is usually the IP address, which corresponds to the 'name' column in ManagedObject)
opmanager_query "SELECT viewname, entity FROM CustomViewProps;" > /tmp/db_custom_view_props.txt 2>/dev/null || echo "" > /tmp/db_custom_view_props.txt

# ------------------------------------------------------------
# 3. Assemble JSON Result
# ------------------------------------------------------------
echo "[export] Assembling JSON..."
python3 << 'PYEOF'
import json

def load_json(path):
    try:
        with open(path) as f: return json.load(f)
    except: return {}

def load_text(path):
    try:
        with open(path) as f: return f.read()
    except: return ""

result = {
    "api_devices": load_json("/tmp/api_devices.json"),
    "api_groups": load_json("/tmp/api_groups.json"),
    "db_managed_objects": load_text("/tmp/db_managed_objects.txt"),
    "db_custom_view": load_text("/tmp/db_custom_view.txt"),
    "db_custom_view_props": load_text("/tmp/db_custom_view_props.txt")
}

with open("/tmp/asset_decommission_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/asset_decommission_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/asset_decommission_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Complete. Result written to $RESULT_FILE"