#!/bin/bash
# export_result.sh — Facility Floorplan Mapping
# Collects mapping data from the OpManager API and PostgreSQL database.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/floorplan_mapping_result.json"
TMP_MAP_API="/tmp/_floorplan_api.json"
TMP_MAP_DB="/tmp/_floorplan_db.txt"

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
# 1. Fetch Maps via API (Multiple endpoint attempts)
# ------------------------------------------------------------
echo "[export] Fetching map list via API..."
API_FETCHED=0

for endpoint in \
    "/api/json/maps/listFloorViews" \
    "/api/json/maps/listMaps" \
    "/api/json/maps/getFloorViews"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_MAP_API"
        API_FETCHED=1
        echo "[export] Maps fetched from $endpoint"
        break
    fi
done

if [ "$API_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_MAP_API"
    echo "[export] WARNING: Could not fetch map list from any API endpoint." >&2
fi

# ------------------------------------------------------------
# 2. Query DB for Floor View and Map Symbol tables
# ------------------------------------------------------------
echo "[export] Querying DB for map and floorview tables..."

# Find all map-related tables dynamically
ALL_MAP_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%map%' OR tablename ILIKE '%floor%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Found map tables: $ALL_MAP_TABLES"

{
    echo "=== MAP & FLOORVIEW TABLE SEARCH RESULTS ==="
    echo "All candidate tables: $ALL_MAP_TABLES"
    echo ""

    for tbl in $ALL_MAP_TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
        echo ""
    done
} > "$TMP_MAP_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
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

map_api = load_json("/tmp/_floorplan_api.json")
map_db_raw = load_text("/tmp/_floorplan_db.txt")

result = {
    "map_api": map_api,
    "map_db_raw": map_db_raw
}

with open("/tmp/floorplan_mapping_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/floorplan_mapping_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/floorplan_mapping_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Clean up
rm -f "$TMP_MAP_API" "$TMP_MAP_DB" || true