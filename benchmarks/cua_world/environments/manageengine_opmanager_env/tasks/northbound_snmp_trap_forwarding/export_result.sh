#!/bin/bash
# export_result.sh — Northbound SNMP Trap Forwarding
# Collects device groups and notification profile data from API and PostgreSQL DB.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/trap_forwarding_result.json"
TMP_GROUPS_API="/tmp/_trap_fwd_groups_api.json"
TMP_NOTIF_API="/tmp/_trap_fwd_notif_api.json"
TMP_DB_RAW="/tmp/_trap_fwd_db_raw.txt"

echo "[export] === Exporting Northbound SNMP Trap Forwarding Results ==="

# Take final screenshot
take_screenshot "/tmp/trap_forwarding_final_screenshot.png" || true

# ------------------------------------------------------------
# 1. Obtain API key
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
# 2. Fetch Device Groups via API
# ------------------------------------------------------------
echo "[export] Fetching device groups..."
opmanager_api_get "/api/json/group/listGroups" > "$TMP_GROUPS_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" > "$TMP_GROUPS_API" 2>/dev/null || \
    echo '{}' > "$TMP_GROUPS_API"

# ------------------------------------------------------------
# 3. Fetch Notification Profiles via API
# ------------------------------------------------------------
echo "[export] Fetching notification profiles..."
opmanager_api_get "/api/json/notification/listNotificationProfiles" > "$TMP_NOTIF_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/notification/listNotificationProfiles?apiKey=${API_KEY}" > "$TMP_NOTIF_API" 2>/dev/null || \
    echo '{}' > "$TMP_NOTIF_API"

# ------------------------------------------------------------
# 4. Query DB for Trap, Notification, and Group configuration
# ------------------------------------------------------------
echo "[export] Querying PostgreSQL for detailed trap and group data..."

# We don't know the exact schema, so we query any table that sounds related to traps, actions, profiles, or groups.
TARGET_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%trap%' OR tablename ILIKE '%notif%' OR tablename ILIKE '%action%' OR tablename ILIKE '%profile%' OR tablename ILIKE '%group%' OR tablename ILIKE '%view%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Target tables: $TARGET_TABLES"
> "$TMP_DB_RAW"

for tbl in $TARGET_TABLES; do
    echo "=== TABLE: $tbl ===" >> "$TMP_DB_RAW"
    opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null >> "$TMP_DB_RAW" || true
    echo "" >> "$TMP_DB_RAW"
done

# ------------------------------------------------------------
# 5. Assemble Result JSON
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

result = {
    "groups_api": load_json("/tmp/_trap_fwd_groups_api.json"),
    "notif_api": load_json("/tmp/_trap_fwd_notif_api.json"),
    "db_raw": load_text("/tmp/_trap_fwd_db_raw.txt")
}

with open("/tmp/trap_forwarding_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Safely move result file with proper permissions
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "/tmp/trap_forwarding_result_tmp.json" "$RESULT_FILE" 2>/dev/null || sudo cp "/tmp/trap_forwarding_result_tmp.json" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true

# Cleanup
rm -f "/tmp/trap_forwarding_result_tmp.json" "$TMP_GROUPS_API" "$TMP_NOTIF_API" "$TMP_DB_RAW" || true

echo "[export] Result saved to $RESULT_FILE"
echo "[export] === Export Complete ==="