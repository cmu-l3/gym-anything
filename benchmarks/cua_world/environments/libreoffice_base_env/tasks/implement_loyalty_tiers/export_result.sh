#!/bin/bash
echo "=== Exporting Implement Loyalty Tiers result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database path
DB_PATH="/home/ga/chinook.odb"

# Check if database file exists and was modified
if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c %s "$DB_PATH" 2>/dev/null || echo "0")
    DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    else
        DB_MODIFIED="false"
    fi
else
    DB_EXISTS="false"
    DB_SIZE="0"
    DB_MODIFIED="false"
fi

# Check if LibreOffice is still running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_exists": $DB_EXISTS,
    "db_modified": $DB_MODIFIED,
    "db_size_bytes": $DB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Gracefully close LibreOffice to ensure flush
# (Optional, but good practice before verifier grabs the file)
pkill -f soffice 2>/dev/null || true
sleep 2

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="