#!/bin/bash
echo "=== Exporting Image Map Task Results ==="

# Define paths
FILE_PATH="/home/ga/Documents/Presentations/system_dashboard.odp"
TASK_START_FILE="/tmp/task_start_time.txt"
INITIAL_MTIME_FILE="/tmp/initial_file_mtime.txt"

# 1. Capture final screenshot (Primary Evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check File Metadata
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    
    CURRENT_MTIME=$(stat -c %Y "$FILE_PATH")
    START_TIME=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(cat "$INITIAL_MTIME_FILE" 2>/dev/null || echo "0")
    
    # Check if modified AFTER task start AND different from initial mtime
    if [ "$CURRENT_MTIME" -gt "$START_TIME" ] && [ "$CURRENT_MTIME" -ne "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Check if ImageMap Editor window was ever opened (Optional/Advanced)
# (Difficult to prove retroactively without recording logs, but we can check if it's currently open)
IMAGEMAP_OPEN="false"
if DISPLAY=:1 wmctrl -l | grep -i "ImageMap Editor"; then
    IMAGEMAP_OPEN="true"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_path": "$FILE_PATH",
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "imagemap_window_open": $IMAGEMAP_OPEN,
    "timestamp": $(date +%s)
}
EOF

# Move JSON to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"