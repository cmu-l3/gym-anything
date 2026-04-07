#!/bin/bash
# export_result.sh — Dynamic Asset Tagging and Compliance Grouping
# Collects custom fields, groups, and device property data via API and DB.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/dynamic_asset_tagging_result.json"
TMP_DEVICES_API="/tmp/_tagging_devices.json"
TMP_GROUPS_API="/tmp/_tagging_groups.json"
TMP_DB_DUMP="/tmp/_tagging_db.txt"

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
# 1. Fetch data from API
# ------------------------------------------------------------
echo "[export] Fetching device and group list from API..."
curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" > "$TMP_DEVICES_API" 2>/dev/null || echo '{}' > "$TMP_DEVICES_API"
curl -sf "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" > "$TMP_GROUPS_API" 2>/dev/null || echo '{}' > "$TMP_GROUPS_API"

# ------------------------------------------------------------
# 2. Query DB for fields, properties, and groups
# ------------------------------------------------------------
echo "[export] Querying DB for custom fields and groups..."

# Dynamically discover relevant tables
TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%custom%' OR tablename ILIKE '%field%' OR tablename ILIKE '%prop%' OR tablename ILIKE '%group%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DATABASE DUMP FOR TAGS, FIELDS, AND GROUPS ==="
    for tbl in $TABLES; do
        # Ignore huge system logs that might accidentally match
        if [[ "$tbl" == *"log"* ]] || [[ "$tbl" == *"audit"* ]]; then
            continue
        fi
        echo ""
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done
} > "$TMP_DB_DUMP" 2>&1

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

devices_api = load_json("/tmp/_tagging_devices.json")
groups_api = load_json("/tmp/_tagging_groups.json")
db_dump = load_text("/tmp/_tagging_db.txt")

result = {
    "devices_api": devices_api,
    "groups_api": groups_api,
    "db_dump": db_dump
}

tmp_out = "/tmp/dynamic_asset_tagging_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move securely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/dynamic_asset_tagging_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/dynamic_asset_tagging_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_DEVICES_API" "$TMP_GROUPS_API" "$TMP_DB_DUMP" || true