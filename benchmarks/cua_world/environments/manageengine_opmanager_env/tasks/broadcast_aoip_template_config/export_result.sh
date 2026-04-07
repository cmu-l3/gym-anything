#!/bin/bash
# export_result.sh — Broadcast AoIP Template Config
echo "=== Exporting Broadcast AoIP Template Config Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if type take_screenshot >/dev/null 2>&1; then
    take_screenshot "/tmp/aoip_final_screenshot.png" ga || true
else
    DISPLAY=:1 scrot "/tmp/aoip_final_screenshot.png" 2>/dev/null || true
fi

RESULT_FILE="/tmp/aoip_template_result.json"
TMP_API="/tmp/_aoip_api.json"
TMP_DB="/tmp/_aoip_db.txt"

# ------------------------------------------------------------
# Obtain API key
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    LOGIN_RESP=$(curl -sf -X POST "http://localhost:8060/apiv2/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=Admin%40123" 2>/dev/null || true)
    if [ -n "$LOGIN_RESP" ]; then
        API_KEY=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

# ------------------------------------------------------------
# 1. Fetch devices via API
# ------------------------------------------------------------
curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" > "$TMP_API" 2>/dev/null || echo '{}' > "$TMP_API"

# ------------------------------------------------------------
# 2. Query DB
# ------------------------------------------------------------
{
    echo "=== DEVICE TEMPLATES ==="
    for tbl in devicetemplate opmdevicetemplate devicetype; do
        if type opmanager_query_headers >/dev/null 2>&1; then
            opmanager_query_headers "SELECT * FROM ${tbl} WHERE templatename ILIKE '%lawo%' OR vendorname ILIKE '%lawo%';" 2>/dev/null || true
            opmanager_query_headers "SELECT * FROM ${tbl} ORDER BY typeid DESC LIMIT 20;" 2>/dev/null || true
        fi
    done
    
    echo "=== SYSOIDS ==="
    for tbl in sysoidmap systemoid; do
        if type opmanager_query_headers >/dev/null 2>&1; then
            opmanager_query_headers "SELECT * FROM ${tbl} WHERE sysoid ILIKE '%50536%';" 2>/dev/null || true
        fi
    done

    echo "=== MANAGED OBJECTS ==="
    if type opmanager_query_headers >/dev/null 2>&1; then
        opmanager_query_headers "SELECT * FROM managedobject WHERE name ILIKE '%studio%' OR ipaddress='127.0.0.1';" 2>/dev/null || true
    fi
} > "$TMP_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble JSON Result
# ------------------------------------------------------------
python3 << 'PYEOF'
import json

def load_json(p):
    try:
        with open(p) as f: return json.load(f)
    except: return {}

def load_text(p):
    try:
        with open(p) as f: return f.read()
    except: return ""

res = {
    "devices_api": load_json("/tmp/_aoip_api.json"),
    "db_raw": load_text("/tmp/_aoip_db.txt")
}
with open("/tmp/aoip_template_result.json", "w") as f:
    json.dump(res, f, indent=2)
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "[export] Results saved to $RESULT_FILE"