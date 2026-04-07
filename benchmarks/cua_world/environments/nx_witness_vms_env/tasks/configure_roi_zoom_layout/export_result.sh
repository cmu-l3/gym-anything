#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Refresh token to ensure we can query result
refresh_nx_token > /dev/null 2>&1 || true

# 1. Query for the specific layout
LAYOUT_NAME="Lobby POS Monitor"
LAYOUT_JSON=$(get_layout_by_name "$LAYOUT_NAME")

# 2. If layout exists, save it to a temp file
LAYOUT_FOUND="false"
if [ -n "$LAYOUT_JSON" ] && [ "$LAYOUT_JSON" != "null" ]; then
    LAYOUT_FOUND="true"
    echo "$LAYOUT_JSON" > /tmp/layout_result.json
else
    echo "{}" > /tmp/layout_result.json
fi

# 3. Get the Target Camera ID (to verify items link to correct camera)
TARGET_CAM_ID=$(cat /tmp/target_camera_id.txt 2>/dev/null || echo "")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create consolidated result JSON
TEMP_JSON=$(mktemp /tmp/final_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "layout_found": $LAYOUT_FOUND,
    "layout_data": $(cat /tmp/layout_result.json),
    "target_camera_id": "$TARGET_CAM_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/layout_result.json

echo "Result exported to /tmp/task_result.json"