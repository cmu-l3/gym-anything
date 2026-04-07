#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ABOOKS=$(cat /tmp/initial_abook_count.txt 2>/dev/null || echo "1")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

CSV_PATH="/home/ga/Documents/techexpo_leads.csv"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
NEW_ABOOK_CREATED="false"

# Check if CSV exists and when it was created
if [ -f "$CSV_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Check if a new address book database was created internally
PROFILE_DIR="/home/ga/.thunderbird/default-release"
CURRENT_ABOOKS=$(ls -1 "$PROFILE_DIR"/abook*.sqlite 2>/dev/null | wc -l)
if [ "$CURRENT_ABOOKS" -gt "$INITIAL_ABOOKS" ]; then
    NEW_ABOOK_CREATED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "new_abook_created": $NEW_ABOOK_CREATED
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# If CSV exists, copy it to tmp so verifier can read it via copy_from_env
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$CSV_PATH" /tmp/techexpo_leads.csv 2>/dev/null || sudo cp "$CSV_PATH" /tmp/techexpo_leads.csv
    chmod 666 /tmp/techexpo_leads.csv 2>/dev/null || sudo chmod 666 /tmp/techexpo_leads.csv 2>/dev/null || true
fi

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="