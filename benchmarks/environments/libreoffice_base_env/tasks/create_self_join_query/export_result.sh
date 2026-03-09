#!/bin/bash
echo "=== Exporting create_self_join_query results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (Trajectory evidence)
take_screenshot /tmp/task_final.png

# 2. Check if the ODB file was modified
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$ODB_PATH")
    MOD_TIME=$(stat -c%Y "$ODB_PATH")
    
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Copy the ODB file for verification (The verifier needs to inspect content.xml inside it)
# We copy it to /tmp so the verifier can access it via copy_from_env
cp "$ODB_PATH" /tmp/submitted_chinook.odb 2>/dev/null || true
chmod 644 /tmp/submitted_chinook.odb 2>/dev/null || true

# 4. Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 5. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "odb_exists": true,
    "odb_modified": $FILE_MODIFIED,
    "odb_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "submission_path": "/tmp/submitted_chinook.odb",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json