#!/bin/bash
echo "=== Exporting Auto-Signout Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check for modified configuration files
# Lobby Track likely stores settings in ProgramData (Database) or AppData (User Config)
echo "Searching for modified configuration files..."

SEARCH_PATHS=(
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
    "/home/ga/.wine/drive_c/users/ga/Local Settings/Application Data/Jolly_Technologies"
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies"
)

MODIFIED_FILES="[]"
FOUND_FILES=()

for path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$path" ]; then
        # Find files modified AFTER task start
        # Exclude log files or temp files
        while IFS= read -r file; do
            if [ -n "$file" ]; then
                echo "Found modified file: $file"
                FOUND_FILES+=("$file")
            fi
        done < <(find "$path" -type f -newermt "@$TASK_START" \
            -not -path "*/Logs/*" \
            -not -name "*.log" \
            -not -name "*.tmp" \
            2>/dev/null)
    fi
done

# Convert bash array to JSON array
if [ ${#FOUND_FILES[@]} -gt 0 ]; then
    MODIFIED_FILES="["
    for i in "${!FOUND_FILES[@]}"; do
        file="${FOUND_FILES[$i]}"
        # Escape quotes for JSON
        file_esc=$(echo "$file" | sed 's/"/\\"/g')
        MODIFIED_FILES+="\"$file_esc\""
        if [ $i -lt $((${#FOUND_FILES[@]}-1)) ]; then
            MODIFIED_FILES+=","
        fi
    done
    MODIFIED_FILES+="]"
fi

# 4. Check if settings appear in user.config (text-based check)
# This is best-effort as settings might be binary
CONFIG_CONTENT_MATCH="false"
if [ ${#FOUND_FILES[@]} -gt 0 ]; then
    # Grep for 480 or 8 in modified text files
    if grep -rE "480|8" "${FOUND_FILES[@]}" 2>/dev/null | grep -iE "Time|Out|Duration" > /dev/null; then
        CONFIG_CONTENT_MATCH="true"
    fi
fi

# 5. Check if app is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "modified_files": $MODIFIED_FILES,
    "config_content_match": $CONFIG_CONTENT_MATCH,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="