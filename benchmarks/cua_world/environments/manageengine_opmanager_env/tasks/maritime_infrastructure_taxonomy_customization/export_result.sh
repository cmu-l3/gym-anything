#!/bin/bash
# export_result.sh — Maritime Infrastructure Taxonomy Customization
# Collects device categories from the DB and API, and checks for uploaded files.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/maritime_taxonomy_result.json"

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
# 1. Fetch categories from API
# ------------------------------------------------------------
echo "[export] Fetching device categories from API..."
API_JSON=$(curl -sf "http://localhost:8060/api/json/admin/deviceCategories?apiKey=${API_KEY}" 2>/dev/null || echo '{}')
echo "$API_JSON" > /tmp/_categories_api.json

# ------------------------------------------------------------
# 2. Query DB for category-related tables
# ------------------------------------------------------------
echo "[export] Querying DB for category tables..."
{
    TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%category%' OR tablename ILIKE '%devicetype%') ORDER BY tablename;" 2>/dev/null || true)
    for tbl in $TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"$tbl\" LIMIT 200;" 2>/dev/null || true
    done
} > /tmp/_categories_db.txt 2>&1

# ------------------------------------------------------------
# 3. Check for uploaded files in OpManager directories
# ------------------------------------------------------------
echo "[export] Checking for uploaded icon files..."
OPMANAGER_DIR=$(cat /tmp/opmanager_install_dir 2>/dev/null || echo "/opt/ManageEngine/OpManager")

# Find occurrences of the file names inside the OpManager directory
# Only counting files that match exactly the icon names
UPLOADED_VSAT=$(find "$OPMANAGER_DIR" -type f -name "vsat_terminal.png" 2>/dev/null | wc -l)
UPLOADED_IOT=$(find "$OPMANAGER_DIR" -type f -name "iot_gateway.png" 2>/dev/null | wc -l)
UPLOADED_RADAR=$(find "$OPMANAGER_DIR" -type f -name "marine_radar.png" 2>/dev/null | wc -l)

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << PYEOF
import json, os

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except:
        return ""

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return {}

result = {
    "categories_api": load_json("/tmp/_categories_api.json"),
    "categories_db_raw": load_text("/tmp/_categories_db.txt"),
    "uploads": {
        "vsat": int("$UPLOADED_VSAT"),
        "iot": int("$UPLOADED_IOT"),
        "radar": int("$UPLOADED_RADAR")
    }
}

with open("/tmp/maritime_taxonomy_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/maritime_taxonomy_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/maritime_taxonomy_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"