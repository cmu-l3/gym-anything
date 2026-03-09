#!/bin/bash
echo "=== Exporting inspect_vehicle_route result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if sumo-gui is still running
SUMO_RUNNING="false"
if is_sumo_gui_running; then
    SUMO_RUNNING="true"
fi

# Check for any parameter dialog windows
PARAM_DIALOG_OPEN="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "parameter\|object\|vehicle"; then
    PARAM_DIALOG_OPEN="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sumo_running": $SUMO_RUNNING,
    "param_dialog_open": $PARAM_DIALOG_OPEN,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="
