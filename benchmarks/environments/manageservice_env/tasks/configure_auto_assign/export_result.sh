#!/bin/bash
echo "=== Exporting configure_auto_assign result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# ==============================================================================
# EXTRACT DATABASE STATE
# ==============================================================================

# 1. Check Auto Assign Status
# Expecting 'true' if enabled
CURRENT_STATUS=$(sdp_db_exec "SELECT param_value FROM GlobalConfig WHERE param_name='AUTO_ASSIGN_STATUS';" 2>/dev/null | tr -d '[:space:]')

# 2. Check Auto Assign Model/Method
# Expecting 'Round Robin' or a code representing it. We grab the value associated with model.
# Common param name is AUTO_ASSIGN_MODEL or similar.
CURRENT_MODEL=$(sdp_db_exec "SELECT param_value FROM GlobalConfig WHERE param_name='AUTO_ASSIGN_MODEL';" 2>/dev/null | tr -d '[:space:]')
# Fallback: Dump all AUTO_ASSIGN params to be safe
ALL_PARAMS=$(sdp_db_exec "SELECT param_name, param_value FROM GlobalConfig WHERE param_name LIKE '%AUTO_ASSIGN%';" 2>/dev/null)

# 3. Check Administrator Exclusion
# We verify if the Admin ID exists in the TechAutoAssignExclude table
ADMIN_ID=$(sdp_db_exec "SELECT account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator';" 2>/dev/null | head -n 1)
IS_EXCLUDED="false"

if [ -n "$ADMIN_ID" ]; then
    EXCLUSION_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM TechAutoAssignExclude WHERE technician_id = $ADMIN_ID;" 2>/dev/null | tr -d '[:space:]')
    if [ "$EXCLUSION_COUNT" -gt "0" ]; then
        IS_EXCLUDED="true"
    fi
fi

# 4. Check App State
APP_RUNNING="false"
if pgrep -f "java" > /dev/null && wait_for_sdp_https 1; then
    APP_RUNNING="true"
fi

# ==============================================================================
# GENERATE JSON RESULT
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "db_check": {
        "status": "$CURRENT_STATUS",
        "model": "$CURRENT_MODEL",
        "admin_id": "$ADMIN_ID",
        "is_admin_excluded": $IS_EXCLUDED,
        "all_params_dump": "$(echo "$ALL_PARAMS" | sed 's/"/\\"/g')"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="