#!/bin/bash
echo "=== Exporting Design Vertical Badge Result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/design_vertical_badge_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Search for the created file
echo "Searching for Vertical_Standard template..."
# Search recursively in the Wine C: drive for the file
# Exclude recent files shortcuts (.lnk)
FOUND_FILES=$(find /home/ga/.wine/drive_c -name "Vertical_Standard*" -not -name "*.lnk" 2>/dev/null)

FILE_EXISTS="false"
FILE_PATH=""
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
IS_PORTRAIT_HINT="false"

if [ -n "$FOUND_FILES" ]; then
    # Pick the most likely candidate (largest file or first one)
    FILE_PATH=$(echo "$FOUND_FILES" | head -n 1)
    echo "Found file at: $FILE_PATH"
    
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created/modified during task."
    else
        echo "WARNING: File is older than task start."
    fi
    
    # Analyze file content for orientation hints
    # Lobby Track templates (.btf) might be binary or proprietary text
    # We look for strings that indicate height/width or orientation
    if strings "$FILE_PATH" | grep -qi "Portrait"; then
        IS_PORTRAIT_HINT="true"
        echo "Found 'Portrait' string in file."
    fi
    
    # Check if we can find dimensions where Height > Width
    # This is a heuristic attempt
    # e.g., looking for "Height=3.5" vs "Width=2.25" patterns if text based
    if grep -aq "Height" "$FILE_PATH"; then
        # Try to extract context
        grep -a -C 2 "Height" "$FILE_PATH" > /tmp/file_context.txt || true
    fi
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" >/dev/null || pgrep -f "Lobby.exe" >/dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$FILE_PATH",
    "file_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "is_portrait_hint": $IS_PORTRAIT_HINT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="