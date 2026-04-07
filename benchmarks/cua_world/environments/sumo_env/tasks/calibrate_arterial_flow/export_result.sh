#!/bin/bash
echo "=== Exporting calibrate_arterial_flow result ==="

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if the calibrator file was created during the task
FILE_CREATED_DURING_TASK="false"
if [ -f "$WORK_DIR/calibrator.add.xml" ]; then
    MTIME=$(stat -c %Y "$WORK_DIR/calibrator.add.xml" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Copy necessary files to /tmp for verifier script access without permission issues
cp "$WORK_DIR/pasubio.rou.xml" /tmp/pasubio.rou.xml 2>/dev/null || true
cp "$WORK_DIR/calibrator.add.xml" /tmp/calibrator.add.xml 2>/dev/null || true
cp "$WORK_DIR/run.sumocfg" /tmp/run.sumocfg 2>/dev/null || true
cp "$OUTPUT_DIR/calibrator_log.xml" /tmp/calibrator_log.xml 2>/dev/null || true

# Set permissions so verifier (running as root or test user) can read them
chmod 644 /tmp/pasubio.rou.xml /tmp/calibrator.add.xml /tmp/run.sumocfg /tmp/calibrator_log.xml 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result with basic state information
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to standardized path
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="