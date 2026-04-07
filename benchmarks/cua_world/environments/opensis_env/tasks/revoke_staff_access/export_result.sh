#!/bin/bash
set -e
echo "=== Exporting Revoke Staff Access results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p'$DB_PASS' $DB_NAME"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check if user still exists (agent shouldn't delete them)
USER_EXISTS_COUNT=$($MYSQL_CMD -N -e "SELECT COUNT(*) FROM staff WHERE first_name='Gerald' AND last_name='Fitzpatrick'" 2>/dev/null || echo "0")

# 2. Check access status
# We check staff_school_info.opensis_access
ACCESS_STATUS=$($MYSQL_CMD -N -e "
    SELECT ssi.opensis_access 
    FROM staff_school_info ssi 
    JOIN staff s ON ssi.staff_id = s.staff_id 
    WHERE s.first_name='Gerald' AND s.last_name='Fitzpatrick'
    LIMIT 1" 2>/dev/null || echo "UNKNOWN")

# 3. Check modification time (anti-gaming) - approximated by checking if state changed
INITIAL_STATUS=$(cat /tmp/initial_access_state.txt 2>/dev/null || echo "UNKNOWN")

WAS_MODIFIED="false"
if [ "$INITIAL_STATUS" == "Y" ] && [ "$ACCESS_STATUS" != "Y" ]; then
    WAS_MODIFIED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_user_exists": $([ "$USER_EXISTS_COUNT" -gt 0 ] && echo "true" || echo "false"),
    "final_access_status": "$ACCESS_STATUS",
    "initial_access_status": "$INITIAL_STATUS",
    "was_modified_during_task": $WAS_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="