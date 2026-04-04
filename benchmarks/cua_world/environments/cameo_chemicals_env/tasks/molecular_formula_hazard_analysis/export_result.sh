#!/bin/bash
echo "=== Exporting Molecular Formula Hazard Analysis results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CSV_PATH="/home/ga/Desktop/isomer_hazards.csv"
TXT_PATH="/home/ga/Desktop/worst_case_analysis.txt"

# Check CSV File
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    else
        CSV_CREATED_DURING_TASK="false"
    fi
else
    CSV_EXISTS="false"
    CSV_CREATED_DURING_TASK="false"
    CSV_SIZE="0"
fi

# Check Text File
if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    else
        TXT_CREATED_DURING_TASK="false"
    fi
else
    TXT_EXISTS="false"
    TXT_CREATED_DURING_TASK="false"
fi

# Check if Firefox is still running (it should be)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location with proper permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy output files to /tmp for easy extraction by verifier (if using copy_from_env on /tmp)
# The verifier pattern allows copying any file, but grouping them helps debugging
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$CSV_PATH" /tmp/isomer_hazards.csv
    chmod 666 /tmp/isomer_hazards.csv
fi
if [ "$TXT_EXISTS" = "true" ]; then
    cp "$TXT_PATH" /tmp/worst_case_analysis.txt
    chmod 666 /tmp/worst_case_analysis.txt
fi

echo "=== Export complete ==="