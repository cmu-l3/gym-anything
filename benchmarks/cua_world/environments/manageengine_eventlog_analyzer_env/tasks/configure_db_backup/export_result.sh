#!/bin/bash
echo "=== Exporting Configure DB Backup results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELA_HOME="/opt/ManageEngine/EventLog"
REPORT_FILE="/home/ga/backup_config_done.txt"
BACKUP_DIR="/opt/ManageEngine/EventLog/backup"
TASK_FINAL_SCREENSHOT="/tmp/task_final.png"

# 1. Take final screenshot
take_screenshot "$TASK_FINAL_SCREENSHOT"

# 2. Check Agent Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_TIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_TIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 5) # First 5 lines
    fi
fi

# 3. Check Backup Directory Existence
BACKUP_DIR_EXISTS="false"
if [ -d "$BACKUP_DIR" ]; then
    BACKUP_DIR_EXISTS="true"
fi

# 4. Check Config File Changes (File System Evidence)
# Count files modified after start time in conf directory
MODIFIED_CONFIG_COUNT=$(find "$ELA_HOME/conf/" -type f -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# 5. Check Database Configuration (Internal State Evidence)
# Query for any backup-related config keys
DB_BACKUP_CONFIG=$(ela_db_query "SELECT * FROM systemconfig WHERE config_key ILIKE '%backup%'" 2>/dev/null || echo "DB_QUERY_FAILED")

# 6. Check if Application is Running
APP_RUNNING="false"
if pgrep -f "WrapperJVMMain" > /dev/null || pgrep -f "java.*EventLog" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result using a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g')",
    "backup_dir_exists": $BACKUP_DIR_EXISTS,
    "backup_dir_path": "$BACKUP_DIR",
    "modified_config_count": $MODIFIED_CONFIG_COUNT,
    "db_backup_config": "$(echo "$DB_BACKUP_CONFIG" | sed 's/"/\\"/g' | tr -d '\n')",
    "app_running": $APP_RUNNING,
    "screenshot_path": "$TASK_FINAL_SCREENSHOT"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="