#!/bin/bash
echo "=== Exporting pan_tilt_disturbance_stiffness Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/pan_tilt_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CSV="/home/ga/Documents/CoppeliaSim/exports/disturbance_timeseries.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/stiffness_report.json"

# Take final screenshot
take_screenshot /tmp/pan_tilt_end_screenshot.png

# Check if files exist and get their properties
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_SIZE=0

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW=true
    fi
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_SIZE=0

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_SIZE=$(stat -c %s "$JSON" 2>/dev/null || echo "0")
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW=true
    fi
fi

# Check if simulation is currently running
SIM_RUNNING=$(is_simulation_running)

# Save the metadata summary to a JSON file for the verifier
# (The verifier will pull the actual CSV and JSON files directly)
cat > /tmp/pan_tilt_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sim_running": $SIM_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_size_bytes": $CSV_SIZE,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_size_bytes": $JSON_SIZE
}
EOF

echo "Export metadata saved to /tmp/pan_tilt_result.json"
cat /tmp/pan_tilt_result.json
echo "=== Export Complete ==="