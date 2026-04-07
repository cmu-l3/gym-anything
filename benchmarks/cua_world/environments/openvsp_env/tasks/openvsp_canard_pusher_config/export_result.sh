#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Kill OpenVSP to release file locks and flush saves
OPENVSP_RUNNING="false"
if pgrep -f "$(get_openvsp_bin)" > /dev/null; then
    OPENVSP_RUNNING="true"
    kill_openvsp
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MODEL_PATH="/home/ga/Documents/OpenVSP/canard_pusher.vsp3"

# Check if model exists and extract contents
if [ -f "$MODEL_PATH" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$MODEL_PATH" 2>/dev/null || echo "0")
    SIZE=$(stat -c %s "$MODEL_PATH" 2>/dev/null || echo "0")
    
    # Extract file content safely using Python
    FILE_CONTENT=$(python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' < "$MODEL_PATH" 2>/dev/null || echo '""')
else
    FILE_EXISTS="false"
    MTIME="0"
    SIZE="0"
    FILE_CONTENT='""'
fi

# Create result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "mtime": $MTIME,
    "file_size": $SIZE,
    "openvsp_running_during_task": $OPENVSP_RUNNING,
    "file_content": $FILE_CONTENT
}
EOF

# Move to final location securely
rm -f /tmp/canard_pusher_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/canard_pusher_result.json
chmod 666 /tmp/canard_pusher_result.json

echo "Result JSON written to /tmp/canard_pusher_result.json"
echo "=== Export complete ==="