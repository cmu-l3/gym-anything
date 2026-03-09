#!/bin/bash
# export_result.sh - Export results for BLEVE Hazard Potential Screening
set -e

echo "=== Exporting BLEVE Screening Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record End Time and Duration
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
DURATION=$((TASK_END - TASK_START))

# 2. Check Output File Status
OUTPUT_PATH="/home/ga/Documents/bleve_risk_assessment.csv"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Verify file was modified AFTER task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "duration_seconds": $DURATION,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move JSON to standard location with safe permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

# 6. Make user file available to verifier (copy to /tmp for easy copy_from_env)
if [ "$OUTPUT_EXISTS" == "true" ]; then
    cp "$OUTPUT_PATH" /tmp/bleve_risk_assessment.csv
    chmod 644 /tmp/bleve_risk_assessment.csv
fi

echo "Result exported to /tmp/task_result.json"