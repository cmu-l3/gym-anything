#!/bin/bash
echo "=== Exporting add_wifi_text_badge result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for modified template files (Evidence of "Save")
# Search for files modified AFTER task start in common Jolly Tech data paths
echo "Searching for modified files..."
MODIFIED_FILES_FOUND="false"
MODIFIED_FILE_LIST=""

# Common paths for Lobby Track data/templates in Wine
SEARCH_PATHS=(
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
    "/home/ga/.wine/drive_c/users/Public/Documents/Jolly Technologies"
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies"
)

# Look for typical design/config extensions or any file in templates dir
# .lbx, .lbl are common, but it might be an .mdb or .xml update
for search_path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$search_path" ]; then
        # Find files modified after TASK_START
        # Exclude common noise like logs
        FOUND=$(find "$search_path" -type f -newermt "@$TASK_START" \
            -not -path "*/Logs/*" \
            -not -name "*.log" \
            -not -name "*.tmp" 2>/dev/null | head -5)
        
        if [ -n "$FOUND" ]; then
            MODIFIED_FILES_FOUND="true"
            MODIFIED_FILE_LIST="$MODIFIED_FILE_LIST $FOUND"
            echo "Found modified files in $search_path: $FOUND"
        fi
    fi
done

# 3. Check if application is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby.exe" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "template_modified": $MODIFIED_FILES_FOUND,
    "modified_files": "$(echo $MODIFIED_FILE_LIST | xargs)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="