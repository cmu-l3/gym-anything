#!/bin/bash
echo "=== Exporting Calibration Task Results ==="

# Load shared utilities
source /home/ga/openbci_task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TARGET_PATH="${RECORDINGS_DIR}/alpha_calibration.txt"

# 3. Analyze Target File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
LINE_COUNT=0
FILE_SIZE=0
IS_OPENBCI_FORMAT="false"

if [ -f "$TARGET_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_PATH")
    FILE_MTIME=$(stat -c %Y "$TARGET_PATH")
    
    # Check creation time vs task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Count lines (excluding comments usually, but simple wc -l is fine for rough check)
    LINE_COUNT=$(wc -l < "$TARGET_PATH")
    
    # Basic format check: look for OpenBCI header markers
    if grep -q "%" "$TARGET_PATH" && grep -q "," "$TARGET_PATH"; then
        IS_OPENBCI_FORMAT="true"
    fi
    
    # Copy file to temp for verifier to inspect content safely
    cp "$TARGET_PATH" /tmp/alpha_calibration_artifact.txt
    chmod 666 /tmp/alpha_calibration_artifact.txt
fi

# 4. Check for left-over raw files (Cleanup check)
# Count how many other files created during the task exist
LEFTOVER_COUNT=$(find "$RECORDINGS_DIR" -name "OpenBCI-RAW-*.txt" -newermt "@$TASK_START" | wc -l)

# 5. Check if App is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "line_count": $LINE_COUNT,
    "file_size_bytes": $FILE_SIZE,
    "is_openbci_format": $IS_OPENBCI_FORMAT,
    "leftover_raw_files": $LEFTOVER_COUNT,
    "app_running": $APP_RUNNING,
    "target_artifact_path": "/tmp/alpha_calibration_artifact.txt"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json