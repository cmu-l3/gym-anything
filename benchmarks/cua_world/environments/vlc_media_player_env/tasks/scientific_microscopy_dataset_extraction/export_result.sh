#!/bin/bash
echo "=== Exporting scientific_microscopy_dataset_extraction result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DATASET_DIR="/home/ga/Pictures/dataset_44B"
ZIP_FILE="/tmp/dataset_44B.zip"
JSON_RESULT="/tmp/task_result.json"

# Check if the target directory exists
DIR_EXISTS="false"
FILES_CREATED_DURING_TASK="false"
FRAME_COUNT=0

if [ -d "$DATASET_DIR" ]; then
    DIR_EXISTS="true"
    
    # Check timestamps to ensure anti-gaming
    NEW_FILES=$(find "$DATASET_DIR" -type f -name "*.png" -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$NEW_FILES" -gt 0 ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
    
    FRAME_COUNT=$(find "$DATASET_DIR" -maxdepth 1 -type f -name "*.png" | wc -l)
    
    # Zip the directory so the verifier can copy it out as a single file
    cd /home/ga/Pictures
    zip -r -q "$ZIP_FILE" "dataset_44B/" 2>/dev/null || true
else
    # Create an empty zip just so the copy doesn't crash
    touch "$ZIP_FILE"
fi

ZIP_EXISTS="false"
if [ -f "$ZIP_FILE" ]; then
    ZIP_EXISTS="true"
fi

# Write summary JSON for the host
cat > "$JSON_RESULT" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "directory_exists": $DIR_EXISTS,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "frame_count_on_disk": $FRAME_COUNT,
    "zip_exported": $ZIP_EXISTS
}
EOF

# Ensure permissions
chmod 666 "$JSON_RESULT" 2>/dev/null || true
chmod 666 "$ZIP_FILE" 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result JSON saved to $JSON_RESULT"
cat "$JSON_RESULT"
echo "=== Export complete ==="