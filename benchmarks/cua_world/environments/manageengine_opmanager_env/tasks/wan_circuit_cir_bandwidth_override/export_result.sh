#!/bin/bash
# export_result.sh — WAN Circuit CIR Bandwidth Override
echo "=== Exporting WAN Circuit CIR Bandwidth Override Results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/wan_circuit_result.json"

# Capture final screenshot
take_screenshot "/tmp/task_final.png" || true

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
        API_KEY=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

# ------------------------------------------------------------
# Fetch Device List from API
# ------------------------------------------------------------
echo "[export] Fetching device list..."
opmanager_api_get "/api/json/device/listDevices" > /tmp/devices.json 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" > /tmp/devices.json 2>/dev/null || \
    echo '{}' > /tmp/devices.json

# ------------------------------------------------------------
# Dump Interface and Threshold tables from DB
# ------------------------------------------------------------
echo "[export] Querying DB tables..."
opmanager_query_headers "SELECT * FROM managedobject LIMIT 2000;" > /tmp/db_dump.txt 2>/dev/null || true
echo -e "\n\n" >> /tmp/db_dump.txt

# Dynamically enumerate all tables containing interface or threshold metadata
IF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%interface%' OR tablename ILIKE '%ifprop%' OR tablename ILIKE '%thresh%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

for tbl in $IF_TABLES; do
    echo "=== TABLE: $tbl ===" >> /tmp/db_dump.txt
    opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 1000;" >> /tmp/db_dump.txt 2>/dev/null || true
    echo -e "\n\n" >> /tmp/db_dump.txt
done

# ------------------------------------------------------------
# Assemble JSON
# ------------------------------------------------------------
echo "[export] Assembling JSON..."
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
    "devices_api": load_json("/tmp/devices.json"),
    "db_raw": load_text("/tmp/db_dump.txt")
}

with open("/tmp/wan_circuit_result_tmp.json", "w") as f:
    json.dump(result, f)
PYEOF

mv /tmp/wan_circuit_result_tmp.json "$RESULT_FILE" 2>/dev/null || cp /tmp/wan_circuit_result_tmp.json "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
echo "=== Export complete ==="