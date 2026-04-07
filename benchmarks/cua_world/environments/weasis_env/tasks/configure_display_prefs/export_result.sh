#!/bin/bash
echo "=== Exporting configure_display_prefs task result ==="

source /workspace/scripts/task_utils.sh

# Record end state screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps and sizes
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TEXT_FILE="/home/ga/DICOM/exports/prefs_changes.txt"
IMAGE_FILE="/home/ga/DICOM/exports/prefs_verification.png"

TEXT_EXISTS="false"
TEXT_CREATED_DURING_TASK="false"
TEXT_CONTENT=""

IMAGE_EXISTS="false"
IMAGE_CREATED_DURING_TASK="false"
IMAGE_SIZE=0

if [ -f "$TEXT_FILE" ]; then
    TEXT_EXISTS="true"
    TEXT_MTIME=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$TEXT_MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING_TASK="true"
    fi
    # Read up to 500 bytes to avoid giant files breaking JSON
    TEXT_CONTENT=$(head -n 20 "$TEXT_FILE" | tr -d '\000-\011\013-\037' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
fi

if [ -f "$IMAGE_FILE" ]; then
    IMAGE_EXISTS="true"
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_FILE" 2>/dev/null || echo "0")
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
    IMAGE_SIZE=$(stat -c %s "$IMAGE_FILE" 2>/dev/null || echo "0")
fi

# Capture final Weasis Configs
WEASIS_PREFS_DIR="/home/ga/.weasis"
SNAP_PREFS_DIR="/home/ga/snap/weasis/current/.weasis"
find "$WEASIS_PREFS_DIR" "$SNAP_PREFS_DIR" -type f \( -name "*.xml" -o -name "*.properties" \) -exec cat {} + 2>/dev/null > /tmp/final_weasis_configs.txt

# Extract config text (sanitized for JSON inclusion)
FINAL_CONFIGS=$(cat /tmp/final_weasis_configs.txt | tr -d '\000-\011\013-\037' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

# Create the result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "text_file_exists": $TEXT_EXISTS,
    "text_created_during_task": $TEXT_CREATED_DURING_TASK,
    "text_content": "$TEXT_CONTENT",
    "image_file_exists": $IMAGE_EXISTS,
    "image_created_during_task": $IMAGE_CREATED_DURING_TASK,
    "image_size_bytes": $IMAGE_SIZE,
    "final_configs": "$FINAL_CONFIGS",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="