#!/bin/bash
set -e
echo "=== Exporting create_denormalized_table results ==="

ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if ODB file exists and was modified
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"
CURRENT_MD5=""

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c%s "$ODB_PATH")
    
    # Check modification time
    ODB_MTIME=$(stat -c%Y "$ODB_PATH")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        # Double check with MD5
        CURRENT_MD5=$(md5sum "$ODB_PATH" | awk '{print $1}')
        INITIAL_MD5=$(cat /tmp/initial_odb_md5.txt 2>/dev/null || echo "")
        
        if [ "$CURRENT_MD5" != "$INITIAL_MD5" ]; then
            ODB_MODIFIED="true"
        fi
    fi
fi

# Check if LibreOffice is still running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json /home/ga/chinook.odb 2>/dev/null || true

echo "Result summary saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="