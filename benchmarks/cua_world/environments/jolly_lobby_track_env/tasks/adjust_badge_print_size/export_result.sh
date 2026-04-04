#!/bin/bash
echo "=== Exporting adjust_badge_print_size results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check for modified configuration files
echo "Checking for modified files..."
MODIFIED_FILES="[]"
TARGET_VALUES_FOUND="false"
FOUND_WIDTH="false"
FOUND_HEIGHT="false"
FOUND_MARGIN="false"

# Find files modified after task start
# We focus on the Wine prefix where the app is installed
search_files=$(find /home/ga/.wine/drive_c -type f -newermt "@$TASK_START" -not -path "*/temp/*" -not -path "*/Temp/*" 2>/dev/null | head -n 20)

if [ -n "$search_files" ]; then
    # Convert newline separated list to JSON array
    MODIFIED_FILES=$(echo "$search_files" | jq -R . | jq -s .)
    
    # Grep for our specific values in these modified files
    # 3.5 (width), 2.25 (height), 0.1 (margin)
    # Note: Values might be stored as "3.50", "3.5", etc.
    
    echo "Searching modified files for target values..."
    if grep -r "3\.5" $search_files > /dev/null 2>&1; then
        FOUND_WIDTH="true"
    fi
    if grep -r "2\.25" $search_files > /dev/null 2>&1; then
        FOUND_HEIGHT="true"
    fi
    if grep -r "0\.1" $search_files > /dev/null 2>&1; then
        FOUND_MARGIN="true"
    fi
    
    if [ "$FOUND_WIDTH" = "true" ] || [ "$FOUND_HEIGHT" = "true" ]; then
        TARGET_VALUES_FOUND="true"
    fi
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "modified_files_detected": $(if [ -n "$search_files" ]; then echo "true"; else echo "false"; fi),
    "target_values_found_in_config": $TARGET_VALUES_FOUND,
    "found_width": $FOUND_WIDTH,
    "found_height": $FOUND_HEIGHT,
    "found_margin": $FOUND_MARGIN,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="