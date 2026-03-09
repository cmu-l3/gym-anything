#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File (Name Identification)
OUTPUT_FILE="/home/ga/Documents/key_owner.txt"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | head -n 1) # Read first line
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Database Modification (Record Update)
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack.sdf" 2>/dev/null | head -1)
DB_MODIFIED="false"
NOTE_FOUND_IN_DB="false"

if [ -f "$DB_FILE" ]; then
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    INITIAL_DB_MTIME=$(cat /tmp/db_initial_mtime.txt 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -gt "$INITIAL_DB_MTIME" ] && [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # 3. Check for specific text in the binary DB file using strings
    # The note "Lost keys returned to owner" should appear if saved
    if strings -e l "$DB_FILE" | grep -qi "Lost keys returned to owner"; then
        NOTE_FOUND_IN_DB="true"
    elif strings "$DB_FILE" | grep -qi "Lost keys returned to owner"; then
        # Check standard ASCII if wide char check fails
        NOTE_FOUND_IN_DB="true"
    fi
fi

# 4. Check if App is Running
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_content": "$(echo "$OUTPUT_CONTENT" | sed 's/"/\\"/g')",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "db_modified": $DB_MODIFIED,
    "note_found_in_db": $NOTE_FOUND_IN_DB,
    "app_running": $APP_RUNNING,
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
echo "=== Export complete ==="