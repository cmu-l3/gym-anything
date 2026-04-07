#!/bin/bash
# export_result.sh — FIPS Compliant SNMPv3 Credential Migration

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/snmpv3_migration_result.json"
TMP_CRED_API="/tmp/_snmpv3_cred_api.json"
TMP_CRED_DB="/tmp/_snmpv3_cred_db.txt"

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
echo "[export] Fetching credential list from API..."
opmanager_api_get "/api/json/credential/listCredentials" > "$TMP_CRED_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/credential/listCredentials?apiKey=${API_KEY}" \
         > "$TMP_CRED_API" 2>/dev/null || \
    echo '{}' > "$TMP_CRED_API"

# ------------------------------------------------------------
# 2. Query DB for credential tables
# ------------------------------------------------------------
echo "[export] Querying DB for credential tables..."

ALL_CRED_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%credential%' OR tablename ILIKE '%snmpv3%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== CREDENTIAL TABLES SEARCH RESULTS ==="
    for tbl in $ALL_CRED_TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > "$TMP_CRED_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
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

cred_api = load_json("/tmp/_snmpv3_cred_api.json")
cred_db_raw = load_text("/tmp/_snmpv3_cred_db.txt")

result = {
    "credentials_api": cred_api,
    "credentials_db_raw": cred_db_raw
}

tmp_out = "/tmp/snmpv3_migration_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/snmpv3_migration_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/snmpv3_migration_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_CRED_API" "$TMP_CRED_DB" || true