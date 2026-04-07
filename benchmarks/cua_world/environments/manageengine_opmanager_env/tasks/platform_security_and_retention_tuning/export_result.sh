#!/bin/bash
# export_result.sh — Platform Security and Retention Tuning
# Collects API and DB settings for DB maintenance and system settings.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/platform_tuning_result.json"
TMP_API="/tmp/_platform_tuning_api.json"
TMP_DB="/tmp/_platform_tuning_db.txt"

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
# 1. Fetch from APIs
# ------------------------------------------------------------
echo "[export] Fetching configuration from APIs..."
DB_PRUNING_API=$(curl -sf "http://localhost:8060/api/json/admin/getDatabaseMaintenanceSettings?apiKey=${API_KEY}" 2>/dev/null || echo "{}")
SYSTEM_SETTINGS_API=$(curl -sf "http://localhost:8060/api/json/admin/getSystemSettings?apiKey=${API_KEY}" 2>/dev/null || echo "{}")
# Also try v2 endpoints if available
DB_PRUNING_APIV2=$(curl -sf "http://localhost:8060/api/v2/settings/databasemaintenance?apiKey=${API_KEY}" 2>/dev/null || echo "{}")
SYSTEM_SETTINGS_APIV2=$(curl -sf "http://localhost:8060/api/v2/settings/systemsettings?apiKey=${API_KEY}" 2>/dev/null || echo "{}")

cat > "$TMP_API" << EOF
{
  "db_pruning_api": $DB_PRUNING_API,
  "system_settings_api": $SYSTEM_SETTINGS_API,
  "db_pruning_api_v2": $DB_PRUNING_APIV2,
  "system_settings_api_v2": $SYSTEM_SETTINGS_APIV2
}
EOF

# ------------------------------------------------------------
# 2. Query DB
# ------------------------------------------------------------
echo "[export] Querying DB for relevant tables..."
ALL_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%global%' OR tablename ILIKE '%system%' OR tablename ILIKE '%prun%' OR tablename ILIKE '%maintain%' OR tablename ILIKE '%maintenance%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Candidate tables: $ALL_TABLES"

{
    echo "=== DB TABLE CONTENTS ==="
    for tbl in $ALL_TABLES; do
        if [ -n "$tbl" ]; then
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
        fi
    done
} > "$TMP_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
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

api_data = load_json("/tmp/_platform_tuning_api.json")
db_raw = load_text("/tmp/_platform_tuning_db.txt")

result = {
    "api_data": api_data,
    "db_raw": db_raw
}

with open("/tmp/platform_tuning_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/platform_tuning_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/platform_tuning_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Clean up
rm -f "$TMP_API" "$TMP_DB" "/tmp/platform_tuning_result_tmp.json" || true