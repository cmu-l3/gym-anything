#!/bin/bash
echo "=== Exporting build_highway_merge result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

WORK_DIR="/home/ga/SUMO_Output/highway_merge"

# Collect metadata into JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "work_dir_exists": $([ -d "$WORK_DIR" ] && echo "true" || echo "false")
}
EOF

# Move to safe location with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Archive the working directory to extract and parse in the verifier
if [ -d "$WORK_DIR" ]; then
    tar -czf /tmp/highway_merge_files.tar.gz -C "$WORK_DIR" . 2>/dev/null || true
    chmod 666 /tmp/highway_merge_files.tar.gz 2>/dev/null || sudo chmod 666 /tmp/highway_merge_files.tar.gz 2>/dev/null || true
fi

echo "=== Export complete ==="