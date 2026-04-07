#!/bin/bash
echo "=== Exporting enforce_visual_naming_conventions task result ==="
source /workspace/scripts/task_utils.sh

# Capture visual proof of final state
take_screenshot /tmp/task_end_screenshot.png

# Fetch the final system state via REST API
echo "Recording final system state..."
ac_login
ac_api GET "/users" > /tmp/final_users.json
ac_api GET "/groups" > /tmp/final_groups.json

# Ensure permissions
chmod 666 /tmp/final_users.json /tmp/final_groups.json

# Aggregate task timeline metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create a master result payload
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "has_start_screenshot": $([ -f "/tmp/task_start_screenshot.png" ] && echo "true" || echo "false"),
    "has_end_screenshot": $([ -f "/tmp/task_end_screenshot.png" ] && echo "true" || echo "false")
}
EOF

chmod 666 /tmp/task_result.json

echo "=== Export complete ==="