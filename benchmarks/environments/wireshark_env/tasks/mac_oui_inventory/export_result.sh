#!/bin/bash
echo "=== Exporting MAC OUI Inventory results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/captures/mac_inventory_report.txt"
GROUND_TRUTH_PATH="/var/lib/wireshark_ground_truth/ground_truth.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check report file status
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON
# We don't verify logic here, just package state for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_path": "$REPORT_PATH",
    "ground_truth_path": "$GROUND_TRUTH_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to safe location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Ensure ground truth is accessible to verifier (verifier runs outside, but copy_from_env reads inside)
# The verifier script will need to copy both the result JSON, the user report, and the ground truth.
# We'll make sure they are readable.
chmod 644 "$GROUND_TRUTH_PATH" 2>/dev/null || true
chmod 644 "$REPORT_PATH" 2>/dev/null || true

echo "Result export complete."
cat /tmp/task_result.json