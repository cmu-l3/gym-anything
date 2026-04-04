#!/bin/bash
echo "=== Exporting Change Display Language results ==="

# Source timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot (Primary VLM evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check if JStock is running (Task requires restart, so it should be running at end)
APP_RUNNING="false"
if pgrep -f "jstock.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Search for Language/Locale settings in JStock config
# JStock typically stores this in XML files under ~/.jstock/
echo "Searching for language settings in ~/.jstock/ ..."

CONFIG_FILES_MODIFIED="false"
FOUND_GERMAN_CONFIG="false"
MATCHING_FILE=""
MATCHING_CONTENT=""

# Find files modified AFTER task start
MODIFIED_FILES=$(find /home/ga/.jstock -type f -newermt "@$TASK_START" 2>/dev/null)

if [ -n "$MODIFIED_FILES" ]; then
    CONFIG_FILES_MODIFIED="true"
    echo "Modified files detected:"
    echo "$MODIFIED_FILES"

    # Grep for German locale indicators in these modified files
    # Look for: "de", "DE", "Deutsch", "German", "Germany"
    # JStock specific: often uses "language=0" (English) vs other ints, or "country" string
    for file in $MODIFIED_FILES; do
        if grep -qEi "Deutsch|German|language.*de|country.*DE" "$file"; then
            FOUND_GERMAN_CONFIG="true"
            MATCHING_FILE="$file"
            # Extract the matching line for verification context
            MATCHING_CONTENT=$(grep -Ei "Deutsch|German|language.*de|country.*DE" "$file" | head -n 1)
            break
        fi
    done
fi

# 4. Fallback: If no modified file found, search ALL files (in case timestamp logic failed)
if [ "$FOUND_GERMAN_CONFIG" = "false" ]; then
    GREP_RESULT=$(grep -riE "Deutsch|German|language.*de|country.*DE" /home/ga/.jstock 2>/dev/null | head -n 1)
    if [ -n "$GREP_RESULT" ]; then
        # Check if this file was actually modified? 
        # For now, just report it, verifier can decide based on modification flag
        MATCHING_FILE=$(echo "$GREP_RESULT" | cut -d: -f1)
        MATCHING_CONTENT=$(echo "$GREP_RESULT" | cut -d: -f2-)
        # We assume it might be pre-existing if CONFIG_FILES_MODIFIED is false
    fi
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "config_files_modified": $CONFIG_FILES_MODIFIED,
    "found_german_config": $FOUND_GERMAN_CONFIG,
    "matching_config_file": "$MATCHING_FILE",
    "matching_config_content": "$(echo $MATCHING_CONTENT | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="