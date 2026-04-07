#!/bin/bash
# export_result.sh — Dynamic Interface Group Provisioning
# Collects interface group and criteria data from the API and DB,
# then writes /tmp/interface_groups_result.json.

set -euo pipefail
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/interface_groups_result.json"
TMP_API="/tmp/_interface_groups_api.json"
TMP_DB="/tmp/_interface_groups_db.txt"

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
# 1. Fetch group lists via API (Multiple Endpoints)
# ------------------------------------------------------------
echo "[export] Fetching group lists from API..."
API_RESP_ALL="{}"

for endpoint in \
    "/api/json/group/listGroups" \
    "/api/json/interface/listInterfaceGroups" \
    "/api/json/group/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "Endpoint ${endpoint} response fetched."
        API_RESP_ALL=$(python3 -c "
import json, sys
try:
    all_data = json.loads(sys.argv[1])
    new_data = json.loads(sys.argv[2])
    all_data[sys.argv[3]] = new_data
    print(json.dumps(all_data))
except Exception:
    print(sys.argv[1])
" "$API_RESP_ALL" "$RESP" "$endpoint")
    fi
done
echo "$API_RESP_ALL" > "$TMP_API"

# ------------------------------------------------------------
# 2. Query DB for group and criteria tables
# ------------------------------------------------------------
echo "[export] Querying DB for group and criteria tables..."

# Find all tables related to custom groups, criteria, or interface groups
ALL_GROUP_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%group%' OR tablename ILIKE '%criteri%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Discovered group/criteria tables: $ALL_GROUP_TABLES"

{
    echo "=== GROUP & CRITERIA DB DUMP ==="
    for tbl in $ALL_GROUP_TABLES; do
        echo ""
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > "$TMP_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, os

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

api_data = load_json("/tmp/_interface_groups_api.json")
db_raw = load_text("/tmp/_interface_groups_db.txt")

result = {
    "api_data": api_data,
    "db_raw": db_raw,
    "export_timestamp": os.popen('date -u +"%Y-%m-%dT%H:%M:%SZ"').read().strip()
}

tmp_out = "/tmp/interface_groups_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe move
mv "/tmp/interface_groups_result_tmp.json" "$RESULT_FILE"
echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_API" "$TMP_DB" || true