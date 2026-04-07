#!/bin/bash
echo "=== Exporting Configure Corridor Mode results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export full device list state
echo "Fetching final device state..."
refresh_nx_token > /dev/null 2>&1 || true
FINAL_STATE=$(nx_api_get "/rest/v1/devices")

# Save to temp file
echo "$FINAL_STATE" > /tmp/final_devices_state.json

# Create result JSON package
# We verify: 
# 1. Output JSON exists
# 2. Initial map exists
# 3. Timestamps

cat > /tmp/task_result.json << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(date +%s),
    "screenshot_path": "/tmp/task_final.png",
    "initial_map_path": "/tmp/initial_camera_map.json",
    "final_state_path": "/tmp/final_devices_state.json"
}
EOF

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="