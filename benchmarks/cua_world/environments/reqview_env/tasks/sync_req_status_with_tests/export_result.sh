#!/bin/bash
echo "=== Exporting sync_req_status_with_tests result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify the SRS document file in the project
# (We need the one modified by the agent)
PROJECT_PATH=$(find /home/ga/Documents/ReqView -name "sync_status_project" -type d | head -1)
SRS_FILE=$(find "$PROJECT_PATH/documents" -name "SRS.json" 2>/dev/null || find "$PROJECT_PATH" -name "*SRS*.json" | head -1)

# 3. Check for modification (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
SRS_MTIME="0"

if [ -f "$SRS_FILE" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_FILE")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Prepare files for export
# We export:
# - The SRS file (agent's work)
# - The ground truth file (created during setup)
# - Result metadata

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "srs_mtime": $SRS_MTIME,
    "file_modified": $FILE_MODIFIED,
    "srs_path": "$SRS_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Copy generated files to /tmp so they can be copied out by the verifier
# (The verifier uses copy_from_env)
cp "$SRS_FILE" /tmp/srs_result.json 2>/dev/null || true
# Ground truth is already at /tmp/ground_truth.json

# Save result JSON
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result at /tmp/task_result.json"