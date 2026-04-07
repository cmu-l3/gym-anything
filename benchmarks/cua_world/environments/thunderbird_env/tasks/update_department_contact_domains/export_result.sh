#!/bin/bash
set -e
echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TB_PROFILE="/home/ga/.thunderbird/default-release"
DB_FILE="$TB_PROFILE/abook.sqlite"

# Take final screenshot before closing
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Close Thunderbird gracefully so it flushes SQLite DB
echo "Closing Thunderbird..."
su - ga -c "DISPLAY=:1 wmctrl -c 'Address Book'" 2>/dev/null || true
su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
sleep 3

# Force kill if still lingering
pkill -f "thunderbird" 2>/dev/null || true
sleep 1

# Copy DB to /tmp for easy extraction
if [ -f "$DB_FILE" ]; then
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED_DURING_TASK="true"
    else
        DB_MODIFIED_DURING_TASK="false"
    fi
    cp "$DB_FILE" /tmp/abook_final.sqlite
    chmod 666 /tmp/abook_final.sqlite
    DB_EXISTS="true"
else
    DB_EXISTS="false"
    DB_MODIFIED_DURING_TASK="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_exists": $DB_EXISTS,
    "db_modified_during_task": $DB_MODIFIED_DURING_TASK
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported successfully to /tmp/task_result.json and /tmp/abook_final.sqlite"
echo "=== Export complete ==="