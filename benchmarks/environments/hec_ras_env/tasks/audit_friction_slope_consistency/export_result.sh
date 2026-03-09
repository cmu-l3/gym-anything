#!/bin/bash
echo "=== Exporting Audit Friction Slope Consistency results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/hec_ras_results/roughness_audit.csv"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"

# 1. Check Output CSV
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    else
        CSV_CREATED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    CSV_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

# 2. Check if Simulation was run (HDF file created/updated)
if [ -f "$HDF_PATH" ]; then
    HDF_MTIME=$(stat -c %Y "$HDF_PATH" 2>/dev/null || echo "0")
    if [ "$HDF_MTIME" -gt "$TASK_START" ]; then
        SIMULATION_RUN="true"
    else
        SIMULATION_RUN="false"
    fi
else
    SIMULATION_RUN="false"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "simulation_run": $SIMULATION_RUN,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="