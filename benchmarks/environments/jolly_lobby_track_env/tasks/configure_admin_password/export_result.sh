#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Detect modified configuration files
# We look for files modified AFTER the task start time in relevant directories
# Common locations for Jolly Tech data:
# - AppData/Local/Jolly Technologies
# - ProgramData/Jolly Technologies
# - Program Files/Jolly Technologies/Lobby Track
# - My Documents/Lobby Track

echo "Searching for modified files since $TASK_START..."

SEARCH_DIRS=(
    "/home/ga/.wine/drive_c/users/ga/Application Data/Jolly Technologies"
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies"
    "/home/ga/LobbyTrack"
    "/home/ga/.wine/drive_c/users/ga/Local Settings/Application Data/Jolly Technologies"
)

MODIFIED_FILES_JSON="[]"

# Helper to build JSON array of modified files
FILES_FOUND=()
for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        # Find files modified more recently than TASK_START
        # Exclude log files which might change just by running
        while IFS= read -r file; do
            if [ -f "$file" ]; then
                MTIME=$(stat -c %Y "$file")
                if [ "$MTIME" -gt "$TASK_START" ]; then
                    FILENAME=$(basename "$file")
                    # Ignore log files
                    if [[ "$FILENAME" != *.log && "$FILENAME" != *.tmp ]]; then
                        FILES_FOUND+=("\"$file\"")
                        echo "Found modified file: $file ($MTIME)"
                    fi
                fi
            fi
        done < <(find "$dir" -type f -name "*.xml" -o -name "*.ini" -o -name "*.config" -o -name "*.sdf" -o -name "*.mdb" -o -name "*.ldb" 2>/dev/null)
    fi
done

# Check Registry files (user.reg is typically updated when wine shuts down, 
# but we can check if it was touched if the app saves to registry immediately)
USER_REG="/home/ga/.wine/user.reg"
if [ -f "$USER_REG" ]; then
    MTIME=$(stat -c %Y "$USER_REG")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_FOUND+=("\"$USER_REG\"")
        echo "Registry modified: $USER_REG"
    fi
fi

# Construct JSON string for files
if [ ${#FILES_FOUND[@]} -gt 0 ]; then
    JOINED_FILES=$(IFS=,; echo "${FILES_FOUND[*]}")
    MODIFIED_FILES_JSON="[$JOINED_FILES]"
fi

# 3. Check if App is still running (didn't crash)
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
    "app_running": $APP_RUNNING,
    "modified_files": $MODIFIED_FILES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="