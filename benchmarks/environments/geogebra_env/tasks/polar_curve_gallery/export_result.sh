#!/bin/bash
# Export script for Polar Curve Gallery task
set -o pipefail

# Ensure we always create a result file even on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_created_during_task": false,
    "task_start_time": 0,
    "task_end_time": 0,
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Polar Curve Gallery Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Gather timing info
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# 3. Check for the output file
EXPECTED_FILE="/home/ga/Documents/GeoGebra/projects/polar_curves.ggb"
FILE_FOUND="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
FILE_MODIFIED=0

if [ -f "$EXPECTED_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MODIFIED=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    if [ "$TASK_START_TIME" != "0" ] && [ "$FILE_MODIFIED" -ge "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Make a copy for safe keeping/verification
    cp "$EXPECTED_FILE" /tmp/polar_curves_submission.ggb
    chmod 666 /tmp/polar_curves_submission.ggb
else
    # Try to find any recently created .ggb file as fallback
    RECENT=$(find /home/ga/Documents/GeoGebra -name "*.ggb" -newermt "@$TASK_START_TIME" 2>/dev/null | head -1)
    if [ -n "$RECENT" ]; then
        echo "Expected file not found, but found recent file: $RECENT"
        EXPECTED_FILE="$RECENT"
        FILE_FOUND="true"
        FILE_SIZE=$(stat -c%s "$RECENT" 2>/dev/null || echo "0")
        FILE_MODIFIED=$(stat -c%Y "$RECENT" 2>/dev/null || echo "0")
        FILE_CREATED_DURING_TASK="true"
        cp "$RECENT" /tmp/polar_curves_submission.ggb
        chmod 666 /tmp/polar_curves_submission.ggb
    fi
fi

# 4. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_found": $FILE_FOUND,
    "file_path": "$EXPECTED_FILE",
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME,
    "submission_path": "/tmp/polar_curves_submission.ggb"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json