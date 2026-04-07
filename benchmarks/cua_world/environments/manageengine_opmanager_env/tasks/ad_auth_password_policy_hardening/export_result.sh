#!/bin/bash
# export_result.sh — AD Auth & Password Policy Hardening
# Dumps related configuration tables and API responses to evaluate task success.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/ad_security_result.json"
TMP_DB_RAW="/tmp/_ad_security_db.txt"
TMP_API_AUTH="/tmp/_api_auth.json"
TMP_API_PASS="/tmp/_api_pass.json"

# Retrieve API key for API checks
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

echo "[export] Querying DB for AD, Authentication, and Password Policy tables..."

# Find relevant config tables matching the requested domain
ALL_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%domain%' OR tablename ILIKE '%ldap%' OR tablename ILIKE '%ad%' OR tablename ILIKE '%passwordrule%' OR tablename ILIKE '%lockout%' OR tablename ILIKE '%security%' OR tablename ILIKE '%aaa%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== SECURITY CONFIGURATION DB EXPORT ==="
    echo "Tables matched: $ALL_TABLES"
    
    # We dump aaa-related and domain-related tables
    for tbl in $ALL_TABLES; do
        if echo "$tbl" | grep -qiE "domain|ldap|ad|passwordrule|lockout|security|aaapassword|aaalogin"; then
            echo ""
            echo "=== TABLE: $tbl ==="
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
        fi
    done
} > "$TMP_DB_RAW" 2>&1

echo "[export] Querying API endpoints..."
# Best effort fetch for API endpoints that might have this data
opmanager_api_get "/api/json/admin/getADDetails" > "$TMP_API_AUTH" 2>/dev/null || echo '{}' > "$TMP_API_AUTH"
opmanager_api_get "/api/json/admin/getPasswordPolicy" > "$TMP_API_PASS" 2>/dev/null || echo '{}' > "$TMP_API_PASS"

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

db_raw = load_text("/tmp/_ad_security_db.txt")
api_auth = load_json("/tmp/_api_auth.json")
api_pass = load_json("/tmp/_api_pass.json")

result = {
    "db_raw": db_raw,
    "api_auth": api_auth,
    "api_pass": api_pass
}

tmp_out = "/tmp/ad_security_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/ad_security_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/ad_security_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_DB_RAW" "$TMP_API_AUTH" "$TMP_API_PASS" || true