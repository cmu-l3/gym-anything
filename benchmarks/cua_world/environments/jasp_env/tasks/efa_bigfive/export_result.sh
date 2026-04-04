#!/bin/bash
echo "=== Exporting EFA Task Results ==="

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_JASP="/home/ga/Documents/JASP/BigFive_EFA.jasp"
OUTPUT_REPORT="/home/ga/Documents/JASP/efa_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check JASP Output File
JASP_EXISTS="false"
JASP_SIZE=0
JASP_CREATED_DURING="false"

if [ -f "$OUTPUT_JASP" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$OUTPUT_JASP" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$OUTPUT_JASP" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Read first 500 chars of report safely
    REPORT_CONTENT=$(head -c 500 "$OUTPUT_REPORT" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# Check if JASP is still running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null || pgrep -f "JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_size": $JASP_SIZE,
    "jasp_created_during_task": $JASP_CREATED_DURING,
    "jasp_path": "$OUTPUT_JASP",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_content": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy the JASP file to temp for easier extraction by verifier if needed
if [ "$JASP_EXISTS" = "true" ]; then
    cp "$OUTPUT_JASP" /tmp/verification_output.jasp
    chmod 644 /tmp/verification_output.jasp
fi

echo "=== Export complete ==="