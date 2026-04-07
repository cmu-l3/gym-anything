#!/bin/bash
# export_result.sh — Automated Remediation Profiles
# Gathers script status and OpManager notification profile data.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/automated_remediation_result.json"
TMP_NOTIF_DB="/tmp/_remediation_notif_db.txt"
TMP_NOTIF_API="/tmp/_remediation_notif_api.json"

echo "[export] === Exporting Automated Remediation Results ==="

# ------------------------------------------------------------
# 1. Take final screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/automated_remediation_final_screenshot.png" || true

# ------------------------------------------------------------
# 2. Check Playbook Access
# ------------------------------------------------------------
PLAYBOOK_FILE="/home/ga/Desktop/remediation_playbook.txt"
INITIAL_ATIME=$(cat /tmp/playbook_initial_atime.txt 2>/dev/null || echo "0")
CURRENT_ATIME=$(stat -c %X "$PLAYBOOK_FILE" 2>/dev/null || echo "0")

PLAYBOOK_READ="false"
if [ "$CURRENT_ATIME" -gt "$INITIAL_ATIME" ]; then
    PLAYBOOK_READ="true"
fi

# ------------------------------------------------------------
# 3. Verify Shell Scripts
# ------------------------------------------------------------
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

check_script() {
    local path=$1
    local expected_str=$2
    
    local exists="false"
    local is_executable="false"
    local has_content="false"
    local created_during="false"
    
    if [ -f "$path" ]; then
        exists="true"
        [ -x "$path" ] && is_executable="true"
        grep -qi "$expected_str" "$path" && has_content="true"
        
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during="true"
        fi
    fi
    
    echo "{\"exists\": $exists, \"is_executable\": $is_executable, \"has_content\": $has_content, \"created_during\": $created_during}"
}

echo "[export] Checking script artifacts..."
SCRIPT_1_STATUS=$(check_script "/opt/remediation-scripts/restart_snmpd.sh" "systemctl restart snmpd")
SCRIPT_2_STATUS=$(check_script "/opt/remediation-scripts/clear_disk_cache.sh" "drop_caches")
SCRIPT_3_STATUS=$(check_script "/opt/remediation-scripts/check_service_health.sh" "ping -c 3")

# ------------------------------------------------------------
# 4. Fetch Notification Profiles (DB + API)
# ------------------------------------------------------------
# Obtain API key
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

# Fetch via API
echo "[export] Querying API for notification profiles..."
opmanager_api_get "/api/json/notification/listNotificationProfiles" 2>/dev/null > "$TMP_NOTIF_API" || \
    curl -sf "http://localhost:8060/api/json/notification/listNotificationProfiles?apiKey=${API_KEY}" 2>/dev/null > "$TMP_NOTIF_API" || \
    echo '{}' > "$TMP_NOTIF_API"

# Fetch via DB (Profiles and Action execution details)
echo "[export] Querying DB for notification profiles and actions..."
ALL_NOTIF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%' OR tablename ILIKE '%alertprofile%' OR tablename ILIKE '%action%' OR tablename ILIKE '%program%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DB NOTIFICATION / ACTION DUMP ==="
    TABLE_COUNT=0
    for tbl in $ALL_NOTIF_TABLES; do
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 15 ]; then break; fi
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
        echo ""
    done
} > "$TMP_NOTIF_DB" 2>&1

# ------------------------------------------------------------
# 5. Assemble Final JSON Result
# ------------------------------------------------------------
echo "[export] Assembling JSON result..."

python3 << PYEOF
import json, os

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return {}

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except:
        return ""

result = {
    "playbook_read": ${PLAYBOOK_READ},
    "scripts": {
        "restart_snmpd": ${SCRIPT_1_STATUS},
        "clear_disk_cache": ${SCRIPT_2_STATUS},
        "check_service_health": ${SCRIPT_3_STATUS}
    },
    "notification_profiles_api": load_json("${TMP_NOTIF_API}"),
    "notification_profiles_db_raw": load_text("${TMP_NOTIF_DB}")
}

tmp_out = "/tmp/automated_remediation_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/automated_remediation_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/automated_remediation_result_tmp.json" "$RESULT_FILE"
fi

# Cleanup
rm -f "$TMP_NOTIF_DB" "$TMP_NOTIF_API" 2>/dev/null || true

echo "[export] Result written to $RESULT_FILE"
echo "[export] === Export Complete ==="