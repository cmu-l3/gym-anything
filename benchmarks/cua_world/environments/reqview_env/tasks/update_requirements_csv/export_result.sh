#!/bin/bash
echo "=== Exporting update_requirements_csv results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/Documents/ReqView/Drone_Project"
SRS_JSON="$PROJECT_DIR/documents/SRS.json"
GROUND_TRUTH_PATH="/home/ga/.hidden/ground_truth.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SRS_MTIME=$(stat -c %Y "$SRS_JSON" 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 3. Export necessary files for verification
# We need the SRS.json (actual state) and the ground_truth.json (expected state)
# We bundle them into a result JSON or just copy them.
# The verifier uses copy_from_env, so we just ensure they are readable.

cp "$SRS_JSON" /tmp/srs_final.json
cp "$GROUND_TRUTH_PATH" /tmp/ground_truth.json

# 4. Create metadata result file
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "srs_mtime": $SRS_MTIME,
    "screenshot_path": "/tmp/task_final.png",
    "srs_json_path": "/tmp/srs_final.json",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Fix permissions
chmod 644 /tmp/task_result.json /tmp/srs_final.json /tmp/ground_truth.json 2>/dev/null || true

echo "Export complete. Result at /tmp/task_result.json"