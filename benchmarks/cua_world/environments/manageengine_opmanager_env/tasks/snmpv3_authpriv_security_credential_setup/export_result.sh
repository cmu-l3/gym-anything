#!/bin/bash
# export_result.sh — SNMPv3 AuthPriv Security Credential Setup

set -euo pipefail
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/snmpv3_credential_result.json"
TMP_CRED_API="/tmp/_cred_api.json"
TMP_CRED_DB="/tmp/_cred_db.txt"

# ------------------------------------------------------------
# 1. Obtain API key
# ------------------------------------------------------------
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
# 2. Fetch credential profiles from API
# ------------------------------------------------------------
echo "[export] Fetching credentials via API..."
CRED_FETCHED=0

for endpoint in \
    "/api/json/admin/getCredentialProfiles" \
    "/api/json/admin/credentials" \
    "/api/json/credential/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_CRED_API"
        CRED_FETCHED=1
        break
    fi
done

if [ "$CRED_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_CRED_API"
    echo "[export] WARNING: Could not fetch credentials from API." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for credential details
# ------------------------------------------------------------
echo "[export] Querying DB for credentials..."

ALL_CRED_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%snmp%' OR tablename ILIKE '%credential%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== CREDENTIAL TABLES ==="
    for tbl in $ALL_CRED_TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > "$TMP_CRED_DB" 2>&1

take_screenshot "/tmp/task_final.png" || true

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

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
    "credentials_api": api_data,
    "credentials_db_raw": db_raw,
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/snmpv3_credential_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/snmpv3_credential_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/snmpv3_credential_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Done."