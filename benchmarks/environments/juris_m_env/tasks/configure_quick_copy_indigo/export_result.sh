#!/bin/bash
echo "=== Exporting configure_quick_copy_indigo result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Output File
OUTPUT_FILE="/home/ga/Documents/brown_citation.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE="0"
FILE_CREATED_DURING="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
fi

# 2. Check Preferences (Secondary Signal)
# We look for the persistent setting in prefs.js (user.js is only read at startup)
PROFILE_DIR=""
for dir in /home/ga/.jurism/jurism/*.default /home/ga/.zotero/zotero/*.default; do
    if [ -d "$dir" ]; then
        PROFILE_DIR="$dir"
        break
    fi
done

PREF_SETTING=""
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/prefs.js" ]; then
    # Extract the quickCopy setting value
    PREF_SETTING=$(grep "extensions.zotero.export.quickCopy.setting" "$PROFILE_DIR/prefs.js" | cut -d',' -f2- | tr -d ');"\n')
fi

# Escape content for JSON
FILE_CONTENT_ESC=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')
PREF_SETTING_ESC=$(echo "$PREF_SETTING" | sed 's/"/\\"/g')

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING,
    "file_content": "$FILE_CONTENT_ESC",
    "file_size": $FILE_SIZE,
    "pref_setting": "$PREF_SETTING_ESC",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="