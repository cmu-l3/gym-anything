#!/bin/bash
# export_result.sh — User Access Control Setup
# Queries OpManager's AAA (Authentication, Authorization, Accounting) database
# tables and the REST API to verify user creation.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/user_access_result.json"
TMP_API_USERS="/tmp/_api_users.json"
TMP_DB_RAW="/tmp/_db_users_raw.txt"

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
# 2. Fetch Users via API
# ------------------------------------------------------------
echo "[export] Fetching users via API..."
USERS_FETCHED=0

for endpoint in \
    "/api/json/admin/listUsers" \
    "/api/json/v2/users" \
    "/api/json/admin/users" \
    "/api/json/users"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_API_USERS"
        USERS_FETCHED=1
        echo "[export] Users fetched from $endpoint"
        break
    fi
done

if [ "$USERS_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_API_USERS"
    echo "[export] WARNING: Could not fetch users from any API endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for User Data
# ------------------------------------------------------------
echo "[export] Querying PostgreSQL for user tables..."

INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(opmanager_query "SELECT COUNT(*) FROM aaalogin;" 2>/dev/null | tr -d ' ' || echo "0")

{
    echo "=== CONSOLIDATED USER QUERY ==="
    # Attempt a consolidated join query mapping logins to roles and emails
    CONSOLIDATED_QUERY="SELECT al.name as username, au.first_name, ci.emailid, ar.name as role_name \
    FROM aaalogin al \
    LEFT JOIN aaaaccount acc ON al.login_id = acc.login_id \
    LEFT JOIN aaaauthorizedrole aar ON acc.account_id = aar.account_id \
    LEFT JOIN aaarole ar ON aar.role_id = ar.role_id \
    LEFT JOIN aaauser au ON al.user_id = au.user_id \
    LEFT JOIN aaausercontactinfo uci ON au.user_id = uci.user_id \
    LEFT JOIN aaacontactinfo ci ON uci.contactinfo_id = ci.contactinfo_id;"
    
    opmanager_query_headers "$CONSOLIDATED_QUERY" 2>/dev/null || echo "CONSOLIDATED_QUERY_FAILED"
    
    echo ""
    echo "=== RAW TABLE DUMPS ==="
    for tbl in aaalogin aaauser aaausercontactinfo aaacontactinfo aaaaccount aaarole aaaauthorizedrole aaaaccountrole; do
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM ${tbl} LIMIT 100;" 2>/dev/null || echo "TABLE_NOT_FOUND_OR_EMPTY"
        echo ""
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << EOF
import json, sys

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

result = {
    "initial_user_count": "$INITIAL_COUNT",
    "current_user_count": "$CURRENT_COUNT",
    "api_users": load_json("$TMP_API_USERS"),
    "db_users_raw": load_text("$TMP_DB_RAW")
}

tmp_out = "/tmp/user_access_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
EOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/user_access_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/user_access_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_API_USERS" "$TMP_DB_RAW" "/tmp/user_access_result_tmp.json" || true