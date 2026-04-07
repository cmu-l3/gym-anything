#!/bin/bash
# export_result.sh — Broadcast Business View Topology Task Export
# Collects Business Views and Device Groups via API and DB.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/broadcast_topology_result.json"
TMP_VIEWS_API="/tmp/_views_api.json"
TMP_GROUPS_API="/tmp/_groups_api.json"
TMP_DB_RAW="/tmp/_topology_db_raw.txt"

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
# 1. Fetch Business Views from API
# ------------------------------------------------------------
echo "[export] Fetching Business Views from API..."
VIEWS_FETCHED=0
for endpoint in \
    "/api/json/businessview/listBusinessViews" \
    "/api/json/maps/listMaps" \
    "/api/json/views/listViews"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_VIEWS_API"
        VIEWS_FETCHED=1
        echo "[export] Views fetched from $endpoint"
        break
    fi
done
if [ "$VIEWS_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_VIEWS_API"
fi

# ------------------------------------------------------------
# 2. Fetch Device Groups from API
# ------------------------------------------------------------
echo "[export] Fetching Device Groups from API..."
GROUPS_FETCHED=0
RESP=$(opmanager_api_get "/api/json/group/listGroups" 2>/dev/null || \
       curl -sf "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" 2>/dev/null || true)
if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
    echo "$RESP" > "$TMP_GROUPS_API"
    GROUPS_FETCHED=1
else
    echo '{}' > "$TMP_GROUPS_API"
fi

# ------------------------------------------------------------
# 3. Query DB for relevant tables (broad search for verification)
# ------------------------------------------------------------
echo "[export] Querying PostgreSQL for Topology & Group tables..."
{
    echo "=== BUSINESS VIEW TABLES ==="
    VIEW_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%view%' OR tablename ILIKE '%business%' OR tablename ILIKE '%map%' OR tablename ILIKE '%topology%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' || true)
    COUNT=0
    for tbl in $VIEW_TABLES; do
        COUNT=$((COUNT + 1))
        if [ "$COUNT" -gt 10 ]; then break; fi
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
    
    echo "=== GROUP TABLES ==="
    GROUP_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%group%' OR tablename ILIKE '%resource%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' || true)
    COUNT=0
    for tbl in $GROUP_TABLES; do
        COUNT=$((COUNT + 1))
        if [ "$COUNT" -gt 5 ]; then break; fi
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Combine into single JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."
python3 << 'PYEOF'
import json

def load_json(path):
    try:
        with open(path) as f: return json.load(f)
    except:
        return {}

def load_text(path):
    try:
        with open(path) as f: return f.read()
    except:
        return ""

views_api = load_json("/tmp/_views_api.json")
groups_api = load_json("/tmp/_groups_api.json")
db_raw = load_text("/tmp/_topology_db_raw.txt")

result = {
    "views_api": views_api,
    "groups_api": groups_api,
    "db_raw": db_raw
}

with open("/tmp/broadcast_topology_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/broadcast_topology_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/broadcast_topology_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Export complete. Result written to $RESULT_FILE."
rm -f "$TMP_VIEWS_API" "$TMP_GROUPS_API" "$TMP_DB_RAW" || true