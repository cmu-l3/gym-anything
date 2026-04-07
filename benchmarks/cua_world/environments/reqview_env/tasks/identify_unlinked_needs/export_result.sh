#!/bin/bash
echo "=== Exporting Results ==="

# Source shared utils
source /workspace/scripts/task_utils.sh

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Data
REPORT_PATH="/home/ga/Documents/ReqView/gap_analysis_report.txt"
GROUND_TRUTH_PATH="/var/lib/reqview_ground_truth/ground_truth.json"

REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_TIMESTAMP=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 50) # First 50 lines
    FILE_TIMESTAMP=$(stat -c %Y "$REPORT_PATH")
fi

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Create JSON Result
# We will embed the ground truth into the result so the verifier (on host) doesn't need to try and mount the hidden dir
# But wait, verifier uses `copy_from_env`. It's better to leave ground truth in a file and copy it.

cat << EOF > /tmp/task_result.json
{
    "report_exists": $REPORT_EXISTS,
    "file_timestamp": $FILE_TIMESTAMP,
    "task_start_time": $TASK_START_TIME,
    "screenshot_path": "/tmp/task_final.png",
    "report_path": "$REPORT_PATH",
    "ground_truth_path": "$GROUND_TRUTH_PATH"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete."