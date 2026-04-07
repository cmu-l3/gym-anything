#!/bin/bash
set -e

echo "=== Exporting notched_panel_profile task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot of the application state
take_screenshot /tmp/task_final_state.png

# Target file paths
TARGET_FILE="/home/ga/Documents/SolveSpace/notched_panel.slvs"
TMP_COPY="/tmp/notched_panel.slvs"

# Check file existence and metadata
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    # Copy to /tmp to ensure the verifier can read it without permission issues
    cp "$TARGET_FILE" "$TMP_COPY"
    chmod 666 "$TMP_COPY"
else
    # Try case variations or common mistakes just in case
    ALT_FILE=$(find /home/ga/Documents -name "*.slvs" -type f -newermt "@$TASK_START" | head -n 1)
    if [ -n "$ALT_FILE" ]; then
        echo "Found alternative saved file: $ALT_FILE"
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c%s "$ALT_FILE")
        FILE_MTIME=$(stat -c%Y "$ALT_FILE")
        cp "$ALT_FILE" "$TMP_COPY"
        chmod 666 "$TMP_COPY"
    fi
fi

# Create JSON result for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move JSON to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported results to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="