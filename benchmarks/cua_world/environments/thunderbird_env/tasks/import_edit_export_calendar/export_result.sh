#!/bin/bash
echo "=== Exporting calendar task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/updated_schedule.ics"

# 1. Analyze the primary exported file artifact
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Stage file for the verifier to safely read
    cp "$OUTPUT_PATH" /tmp/updated_schedule.ics
    chmod 666 /tmp/updated_schedule.ics 2>/dev/null || true
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

# 2. Dump the Thunderbird Calendar SQLite database (Anti-Gaming verification)
# This proves the edit was performed through Thunderbird's system, not via manual file editing
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -name "*.default*" -o -name "default-release" | head -n 1 2>/dev/null)
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/calendar-data/local.sqlite" ]; then
    sqlite3 "$PROFILE_DIR/calendar-data/local.sqlite" "SELECT value FROM cal_properties" > /tmp/db_dump.txt 2>/dev/null || echo "failed" > /tmp/db_dump.txt
else
    echo "not found" > /tmp/db_dump.txt
fi
chmod 666 /tmp/db_dump.txt 2>/dev/null || true

# Capture final UI state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Export general file properties into a JSON dictionary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE
}
EOF

# Stage the result payload for verifier
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="