#!/bin/bash
echo "=== Exporting Delete Visitor Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task Start: $TASK_START"

# Locate Database File
DB_FILE=$(cat /tmp/db_path.txt 2>/dev/null)
if [ -z "$DB_FILE" ] || [ ! -f "$DB_FILE" ]; then
    # Try finding it again
    DB_FILE=$(find /home/ga/.wine/drive_c -iname "*.mdb" -o -iname "*.sdf" | grep -i "lobby\|visitor\|track" | head -1)
fi

DB_EXISTS="false"
DB_MODIFIED="false"
DB_MTIME="0"
STRINGS_FOUND=""

if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    DB_EXISTS="true"
    DB_MTIME=$(stat -c %Y "$DB_FILE")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Extract strings from DB to check for names
    # (Note: Deleted records might still appear in strings if not compacted, 
    # so presence of 'John Testentry' is not definitive failure, 
    # but absence is definitive success)
    STRINGS_FOUND=$(strings "$DB_FILE" | grep -i "Gonzalez\|Chen\|Williams\|Testentry" || echo "")
fi

# Check if App is running
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "db_exists": $DB_EXISTS,
    "db_path": "$DB_FILE",
    "db_modified": $DB_MODIFIED,
    "db_mtime": $DB_MTIME,
    "app_running": $APP_RUNNING,
    "db_content_sample": $(echo "$STRINGS_FOUND" | jq -R -s '.'),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="