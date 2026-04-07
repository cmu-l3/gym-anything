#!/bin/bash
echo "=== Exporting Ergonomic Dashboard Layout Result ==="

source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture the final screenshot of the state (independent of agent's screenshot)
take_screenshot /tmp/task_final_state.png

# Check if agent's screenshot exists
AGENT_SCREENSHOT="/home/ga/Desktop/dashboard_layout.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
if [ -f "$AGENT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
fi

# Capture Window Geometry Data
# wmctrl -lG format: ID Desktop X Y W H Host Title
# We need this to verify positions and overlap programmatically
WINDOW_DATA=$(DISPLAY=:1 wmctrl -lG 2>/dev/null)

# Check if OpenICE is still running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Create result JSON
# We embed the raw window data to parse in Python
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "window_list_raw": "$(echo "$WINDOW_DATA" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')",
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json