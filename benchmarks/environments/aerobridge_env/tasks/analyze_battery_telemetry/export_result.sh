#!/bin/bash
echo "=== Exporting analyze_battery_telemetry results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/critical_battery_report.csv"
GROUND_TRUTH_PATH="/var/lib/aerobridge/battery_ground_truth.csv"

# Check if agent report exists
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Copy files to temp location for easy retrieval by verifier
# We copy them to /tmp/export_data/
mkdir -p /tmp/export_data
if [ "$REPORT_EXISTS" = "true" ]; then
    cp "$REPORT_PATH" /tmp/export_data/agent_report.csv
fi
if [ -f "$GROUND_TRUTH_PATH" ]; then
    cp "$GROUND_TRUTH_PATH" /tmp/export_data/ground_truth.csv
    GROUND_TRUTH_EXISTS="true"
else
    GROUND_TRUTH_EXISTS="false"
fi

chmod -R 666 /tmp/export_data

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "ground_truth_exists": $GROUND_TRUTH_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "agent_report_path": "/tmp/export_data/agent_report.csv",
    "ground_truth_path": "/tmp/export_data/ground_truth.csv"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"