#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define expected paths
JASP_FILE="/home/ga/Documents/JASP/qc_analysis.jasp"
REPORT_FILE="/home/ga/Documents/JASP/qc_report.txt"

# Check JASP file details
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_CREATED_DURING="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# Check Report file details
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read first line, limit length to avoid massive dumps
    REPORT_CONTENT=$(head -n 1 "$REPORT_FILE" | cut -c 1-100)
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
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export summary:"
cat /tmp/task_result.json
echo "=== Export Complete ==="