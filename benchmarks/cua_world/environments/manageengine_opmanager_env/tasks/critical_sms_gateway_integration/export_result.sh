#!/bin/bash
# export_result.sh — Critical SMS Gateway Integration
# Collects SMS Gateway configuration data from the DB and API,
# then writes to /tmp/sms_gateway_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/sms_gateway_result.json"
TMP_SMS_DB="/tmp/_sms_gateway_db.txt"
TMP_SMS_API="/tmp/_sms_gateway_api.json"

# Take final screenshot
take_screenshot "/tmp/sms_gateway_final_screenshot.png" || true

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
# 2. Query DB for SMS Gateway configuration
# ------------------------------------------------------------
echo "[export] Querying DB for SMS tables..."

# Enumerate all SMS-related tables
ALL_SMS_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%sms%' OR tablename ILIKE '%gateway%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] SMS-related tables found: $ALL_SMS_TABLES"

{
    echo "=== SMS GATEWAY TABLE SEARCH RESULTS ==="
    echo "Tables found: $ALL_SMS_TABLES"
    echo ""

    for tbl in $ALL_SMS_TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 50;" 2>/dev/null || true
    done
} > "$TMP_SMS_DB" 2>&1

# ------------------------------------------------------------
# 3. Fetch SMS configurations via API (best-effort)
# ------------------------------------------------------------
echo "[export] Fetching SMS Gateway configs via API..."
SMS_API_FETCHED=0

for endpoint in \
    "/api/json/admin/getSmsGateway" \
    "/api/json/settings/getSmsGateway" \
    "/api/json/admin/smsGateway" \
    "/api/json/admin/getCustomSmsGateway"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_SMS_API"
        SMS_API_FETCHED=1
        echo "[export] SMS config fetched from $endpoint"
        break
    fi
done

if [ "$SMS_API_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_SMS_API"
    echo "[export] WARNING: Could not fetch SMS Gateway config from API endpoints." >&2
fi

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

sms_db = load_text("/tmp/_sms_gateway_db.txt")
sms_api = load_json("/tmp/_sms_gateway_api.json")

result = {
    "sms_db_raw": sms_db,
    "sms_api": sms_api,
    "timestamp": os.popen("date -u +'%Y-%m-%dT%H:%M:%SZ'").read().strip()
}

tmp_out = "/tmp/sms_gateway_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Copy to final destination
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/sms_gateway_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/sms_gateway_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_SMS_DB" "$TMP_SMS_API" "/tmp/sms_gateway_result_tmp.json" || true