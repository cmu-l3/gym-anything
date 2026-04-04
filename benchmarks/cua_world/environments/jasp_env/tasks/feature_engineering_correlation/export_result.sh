#!/bin/bash
echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/JASP/plasticity_report.txt"
JASP_PATH="/home/ga/Documents/JASP/PlasticityAnalysis.jasp"

# Initialize variables
REPORT_EXISTS="false"
REPORT_CONTENT=""
JASP_EXISTS="false"
JASP_SIZE="0"
FILE_CREATED_DURING_TASK="false"

# Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0) # Encode to avoid JSON breaking
    
    # Check timestamp
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check JASP File
if [ -f "$JASP_PATH" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp (if report wasn't created, check this one)
    JASP_MTIME=$(stat -c %Y "$JASP_PATH" 2>/dev/null || echo "0")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "jasp_exists": $JASP_EXISTS,
    "jasp_size": $JASP_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "dataset_path": "/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"