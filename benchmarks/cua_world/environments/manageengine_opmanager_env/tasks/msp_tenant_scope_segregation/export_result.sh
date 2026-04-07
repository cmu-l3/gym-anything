#!/bin/bash
# export_result.sh — MSP Tenant Scope Segregation
# Collects Business View, User, and Scope mapping data via API and DB.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/msp_tenant_result.json"
TMP_USERS_API="/tmp/_msp_users_api.json"
TMP_BVS_API="/tmp/_msp_bvs_api.json"
TMP_DB_RAW="/tmp/_msp_db_raw.txt"

# ------------------------------------------------------------
# Obtain API key
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
# 1. Fetch Users via API
# ------------------------------------------------------------
echo "[export] Fetching users list via API..."
opmanager_api_get "/api/json/admin/listUsers" > "$TMP_USERS_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/admin/listUsers?apiKey=${API_KEY}" > "$TMP_USERS_API" 2>/dev/null || \
    echo '{}' > "$TMP_USERS_API"

# ------------------------------------------------------------
# 2. Fetch Business Views via API
# ------------------------------------------------------------
echo "[export] Fetching business views via API..."
opmanager_api_get "/api/json/businessview/listBusinessViews" > "$TMP_BVS_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/businessview/listBusinessViews?apiKey=${API_KEY}" > "$TMP_BVS_API" 2>/dev/null || \
    echo '{}' > "$TMP_BVS_API"

# Also try fetching Map list as fallback
opmanager_api_get "/api/json/map/listMaps" >> "$TMP_BVS_API" 2>/dev/null || true

# ------------------------------------------------------------
# 3. Query DB for AAA, Map, and Scope tables
# ------------------------------------------------------------
echo "[export] Querying DB for mapping and scope data..."

{
    echo "=== DB SEARCH RESULTS ==="

    echo "--- Users ---"
    opmanager_query_headers "SELECT * FROM aaalogin LIMIT 100;" 2>/dev/null || true
    opmanager_query_headers "SELECT * FROM aaaaccount LIMIT 100;" 2>/dev/null || true
    opmanager_query_headers "SELECT * FROM aaauser LIMIT 100;" 2>/dev/null || true

    echo "--- Business Views / Maps ---"
    # Find tables matching View or Map
    VIEW_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%businessview%' OR tablename ILIKE '%customview%' OR tablename ILIKE 'map%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    for tbl in $VIEW_TABLES; do
        echo "Table: $tbl"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done

    echo "--- Scope Restrictions ---"
    SCOPE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%scope%' OR tablename ILIKE '%restrict%' OR tablename ILIKE 'aaa%rule%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    for tbl in $SCOPE_TABLES; do
        echo "Table: $tbl"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done

} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, sys, os

def load_json(path):
    try:
        with open(path) as f:
            # Handle concatenated JSON outputs (if fallback wrote to same file)
            content = f.read().strip()
            # If multiple JSON objects, wrap them in list
            if '}{' in content:
                content = '[' + content.replace('}{', '},{') + ']'
            return json.loads(content)
    except Exception:
        return {}

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

result = {
    "users_api": load_json("/tmp/_msp_users_api.json"),
    "business_views_api": load_json("/tmp/_msp_bvs_api.json"),
    "db_raw_dump": load_text("/tmp/_msp_db_raw.txt")
}

tmp_out = "/tmp/msp_tenant_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move file safely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/msp_tenant_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/msp_tenant_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_USERS_API" "$TMP_BVS_API" "$TMP_DB_RAW" || true