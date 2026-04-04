#!/bin/bash
echo "=== Exporting Configure Request Archiving Policy results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Database for Archiving Configuration
# We query multiple potential tables/columns to handle SDP version differences safely.

# Try getting status (expecting 't', 'true', '1', or 'on')
# Note: sdp_db_exec outputs clean results (trimmed)
DB_STATUS=$(sdp_db_exec "SELECT status FROM archive_config WHERE module_id = (SELECT module_id FROM module WHERE module_name = 'Request')")

# If empty, try legacy table
if [ -z "$DB_STATUS" ]; then
    DB_STATUS=$(sdp_db_exec "SELECT enabled FROM archiveconfiguration WHERE module = 'Request'")
fi

# Try getting days (expecting '365')
DB_DAYS=$(sdp_db_exec "SELECT no_of_days FROM archive_config WHERE module_id = (SELECT module_id FROM module WHERE module_name = 'Request')")

if [ -z "$DB_DAYS" ]; then
    DB_DAYS=$(sdp_db_exec "SELECT days FROM archiveconfiguration WHERE module = 'Request'")
fi

# Normalize Status
IS_ENABLED="false"
if [[ "$DB_STATUS" == "t" || "$DB_STATUS" == "true" || "$DB_STATUS" == "1" || "$DB_STATUS" == "on" ]]; then
    IS_ENABLED="true"
fi

# 2. Check if Application is Running
APP_RUNNING="false"
if pgrep -f "WrapperJVMMain" > /dev/null || pgrep -f "wrapper.java" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "db_archiving_enabled": $IS_ENABLED,
    "db_archiving_days": "${DB_DAYS:-0}",
    "db_raw_status": "$DB_STATUS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="