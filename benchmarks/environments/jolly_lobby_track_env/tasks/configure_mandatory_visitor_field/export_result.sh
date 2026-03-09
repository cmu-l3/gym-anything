#!/bin/bash
set -e
echo "=== Exporting Configure Mandatory Visitor Field result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check Database File Status
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack*.sdf" -o -name "LobbyTrack*.mdb" 2>/dev/null | head -1)
DB_MODIFIED="false"
DB_SIZE_CHANGED="false"

if [ -n "$DB_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(cat /tmp/initial_db_mtime.txt 2>/dev/null || echo "0")
    
    CURRENT_SIZE=$(stat -c %s "$DB_FILE" 2>/dev/null || echo "0")
    INITIAL_SIZE=$(cat /tmp/initial_db_size.txt 2>/dev/null || echo "0")

    # Check if modified after start time AND different from initial timestamp
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ] && [ "$CURRENT_MTIME" != "$INITIAL_MTIME" ]; then
        DB_MODIFIED="true"
    fi
    
    if [ "$CURRENT_SIZE" != "$INITIAL_SIZE" ]; then
        DB_SIZE_CHANGED="true"
    fi
    
    echo "DB File: $DB_FILE"
    echo "Timestamps: Initial=$INITIAL_MTIME, Current=$CURRENT_MTIME, Start=$TASK_START"
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_file_found": $([ -n "$DB_FILE" ] && echo "true" || echo "false"),
    "db_modified": $DB_MODIFIED,
    "db_size_changed": $DB_SIZE_CHANGED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="