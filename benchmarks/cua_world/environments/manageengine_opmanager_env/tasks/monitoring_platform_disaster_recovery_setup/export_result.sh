#!/bin/bash
# export_result.sh — Monitoring Platform Disaster Recovery Setup
# Verifies OS directory state, queries OpManager DB for backup configs,
# and attempts to fetch config via API. Outputs to JSON.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/dr_setup_result.json"
TMP_DB_RAW="/tmp/_dr_db_raw.txt"
TMP_API_RAW="/tmp/_dr_api_raw.json"

echo "[export] === Exporting Disaster Recovery Task Results ==="

# ------------------------------------------------------------
# 1. Check OS Directory State
# ------------------------------------------------------------
DIR_PATH="/var/opt/opmanager_backups"
DIR_EXISTS="false"
DIR_PERMS="000"

if [ -d "$DIR_PATH" ]; then
    DIR_EXISTS="true"
    DIR_PERMS=$(stat -c "%a" "$DIR_PATH" 2>/dev/null || echo "000")
    echo "[export] Directory exists with permissions: $DIR_PERMS"
else
    echo "[export] Directory DOES NOT exist."
fi

# ------------------------------------------------------------
# 2. Query OpManager PostgreSQL Database
# ------------------------------------------------------------
echo "[export] Querying DB for backup configuration..."
# Discover tables related to backup or scheduling
TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%backup%' OR tablename ILIKE '%schedule%' OR tablename ILIKE '%archive%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DISCOVERED BACKUP TABLES ==="
    echo "$TABLES"
    
    for tbl in $TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done

    # Also check generic settings tables for backup keys
    echo ""
    echo "=== TABLE: SystemSettings ==="
    opmanager_query_headers "SELECT * FROM \"SystemSettings\" WHERE settingname ILIKE '%backup%' LIMIT 100;" 2>/dev/null || true

    echo ""
    echo "=== TABLE: GlobalSettings ==="
    opmanager_query_headers "SELECT * FROM \"GlobalSettings\" WHERE category ILIKE '%backup%' LIMIT 100;" 2>/dev/null || true
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 3. Try to Fetch Config via API
# ------------------------------------------------------------
echo "[export] Attempting API retrieval..."
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

if [ -n "$API_KEY" ]; then
    # Try a few common endpoints
    for endpoint in "/api/json/admin/getBackupDetails" "/api/json/settings/backup" "/api/json/backup/getSchedule"; do
        RESP=$(curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
        if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
            echo "$RESP" > "$TMP_API_RAW"
            echo "[export] API data fetched from $endpoint"
            break
        fi
    done
fi

if [ ! -f "$TMP_API_RAW" ]; then
    echo "{}" > "$TMP_API_RAW"
fi

# ------------------------------------------------------------
# 4. Final Screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/dr_final_screenshot.png" || true

# ------------------------------------------------------------
# 5. Assemble JSON Result
# ------------------------------------------------------------
echo "[export] Assembling final JSON..."

python3 - "$DIR_EXISTS" "$DIR_PERMS" << 'PYEOF'
import json, sys, os

dir_exists = sys.argv[1]
dir_perms = sys.argv[2]

try:
    with open("/tmp/_dr_db_raw.txt", "r") as f:
        db_raw = f.read()
except Exception:
    db_raw = ""

try:
    with open("/tmp/_dr_api_raw.json", "r") as f:
        api_raw = json.load(f)
except Exception:
    api_raw = {}

result = {
    "dir_exists": dir_exists,
    "dir_perms": dir_perms,
    "db_raw": db_raw,
    "api_raw": api_raw
}

with open("/tmp/dr_setup_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move securely
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "/tmp/dr_setup_result_tmp.json" "$RESULT_FILE" 2>/dev/null || sudo cp "/tmp/dr_setup_result_tmp.json" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "[export] Result written to $RESULT_FILE"
echo "[export] === Export Complete ==="