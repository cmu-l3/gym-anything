#!/bin/bash
echo "=== Exporting Deprecate Legacy Requirements Result ==="

source /workspace/scripts/task_utils.sh

# 1. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Check SRS File Metadata
# The file location depends on the project dir created in setup
# We find the specific project directory used
PROJECT_DIR=$(find /home/ga/Documents/ReqView -name "deprecate_legacy_requirements_project" -type d | head -1)
SRS_FILE="$PROJECT_DIR/documents/SRS.json"

SRS_EXISTS="false"
SRS_MODIFIED="false"
SRS_SIZE="0"

if [ -f "$SRS_FILE" ]; then
    SRS_EXISTS="true"
    SRS_SIZE=$(stat -c %s "$SRS_FILE")
    SRS_MTIME=$(stat -c %Y "$SRS_FILE")
    
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
fi

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_exists": $SRS_EXISTS,
    "srs_modified": $SRS_MODIFIED,
    "srs_size_bytes": $SRS_SIZE,
    "srs_path": "$SRS_FILE",
    "ground_truth_path": "/tmp/legacy_targets.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="