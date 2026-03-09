#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# ============================================================
# Check configuration for "Nimbus" setting
# JStock saves preferences in XML files in ~/.jstock or ~/.java
# We search recursively for the string "Nimbus" in the config dir
# ============================================================
CONFIG_DIR="/home/ga/.jstock"
NIMBUS_FOUND="false"
MATCHING_FILE=""
FILE_MODIFIED_DURING_TASK="false"

# Grep for "Nimbus" (case insensitive just in case, though usually capitalized)
# We look for files containing "Nimbus" that were modified/created recently
if [ -d "$CONFIG_DIR" ]; then
    # Find files modified after task start
    MODIFIED_FILES=$(find "$CONFIG_DIR" -type f -newermt "@$TASK_START")
    
    for file in $MODIFIED_FILES; do
        if grep -qi "Nimbus" "$file"; then
            NIMBUS_FOUND="true"
            MATCHING_FILE="$file"
            FILE_MODIFIED_DURING_TASK="true"
            echo "Found 'Nimbus' in modified file: $file"
            break
        fi
    done
    
    # Fallback: if not found in modified files (maybe file timestamp didn't update yet?),
    # check existence in any file, though this scores lower in verification
    if [ "$NIMBUS_FOUND" = "false" ]; then
        if grep -rQi "Nimbus" "$CONFIG_DIR"; then
            NIMBUS_FOUND="true"
            MATCHING_FILE=$(grep -rli "Nimbus" "$CONFIG_DIR" | head -1)
            # Check timestamp manually
            FILE_MTIME=$(stat -c %Y "$MATCHING_FILE" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
                FILE_MODIFIED_DURING_TASK="true"
            fi
            echo "Found 'Nimbus' in file: $MATCHING_FILE"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "nimbus_config_found": $NIMBUS_FOUND,
    "config_file_path": "$MATCHING_FILE",
    "config_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "initial_screenshot_path": "/tmp/task_initial.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="