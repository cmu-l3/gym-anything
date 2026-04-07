#!/bin/bash
# export_result.sh — Multi-Protocol Credential Store Setup

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/multiprotocol_cred_result.json"
TMP_API="/tmp/_cred_api.json"
TMP_DB="/tmp/_cred_db.txt"

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
# 1. Fetch credentials from API
# ------------------------------------------------------------
echo "[export] Fetching credential lists from API..."

# Create a combined JSON output for all endpoints we try
API_COMBINED="{"

for endpoint in \
    "/api/json/credential/listCredentials" \
    "/api/json/discovery/getCredentials" \
    "/api/json/discovery/listCredentials"; do
    
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    
    # Very simple way to combine valid JSON responses
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        CLEAN_ENDPOINT=$(echo "$endpoint" | tr '/' '_')
        API_COMBINED="${API_COMBINED} \"${CLEAN_ENDPOINT}\": ${RESP},"
        echo "[export] Fetched from $endpoint"
    fi
done

# Remove trailing comma and close object
API_COMBINED=$(echo "$API_COMBINED" | sed 's/,$//')
API_COMBINED="${API_COMBINED} }"
echo "$API_COMBINED" > "$TMP_API"

# ------------------------------------------------------------
# 2. Query DB for credential tables
# ------------------------------------------------------------
echo "[export] Querying DB for credential tables..."

ALL_CRED_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%cred%' OR tablename ILIKE '%protocol%' OR tablename ILIKE '%password%' OR tablename ILIKE '%snmp%' OR tablename ILIKE '%ssh%' OR tablename ILIKE '%telnet%' OR tablename ILIKE '%wmi%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== CREDENTIAL TABLE SEARCH RESULTS ==="
    echo "Tables found: $ALL_CRED_TABLES"
    echo ""

    # Dump contents of relevant tables
    for tbl in $ALL_CRED_TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        echo ""
    done
} > "$TMP_DB" 2>&1

# ------------------------------------------------------------
# 3. Combine into result JSON
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

api_data = load_json("/tmp/_cred_api.json")
db_raw = load_text("/tmp/_cred_db.txt")

result = {
    "api_responses": api_data,
    "db_raw": db_raw
}

tmp_out = "/tmp/multiprotocol_cred_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/multiprotocol_cred_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/multiprotocol_cred_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_API" "$TMP_DB" /tmp/multiprotocol_cred_result_tmp.json || true