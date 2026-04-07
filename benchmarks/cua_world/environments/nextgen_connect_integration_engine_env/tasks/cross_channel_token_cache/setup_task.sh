#!/bin/bash
echo "=== Setting up Cross-Channel Token Cache Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Cleanup previous run artifacts
rm -rf /tmp/authenticated_output
mkdir -p /tmp/authenticated_output
chmod 777 /tmp/authenticated_output
rm -f /tmp/task_result.json

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count

# Wait for NextGen Connect to be responsive
wait_for_api 30

# Open a terminal window for the agent with instructions
DISPLAY=:1 gnome-terminal --geometry=100x40+50+50 -- bash -c '
echo "======================================================="
echo "   NextGen Connect - Shared State Pattern Task"
echo "======================================================="
echo ""
echo "GOAL: Implement cross-channel communication via Global Map"
echo ""
echo "Channel 1: Token_Manager"
echo "  - Source: TCP Listener (Port 6661)"
echo "  - Format: JSON"
echo "  - Action: Extract \"access_token\" -> Store in GlobalMap"
echo "            Key: \"current_bearer_token\""
echo ""
echo "Channel 2: Data_Sender"
echo "  - Source: TCP Listener (Port 6662)"
echo "  - Format: HL7 v2.x"
echo "  - Action: Read \"current_bearer_token\" from GlobalMap"
echo "  - Dest:   Write to file /tmp/authenticated_output/..."
echo "            Content: \"Authorization: Bearer <TOKEN>\\n<HL7_MSG>\""
echo ""
echo "REST API: https://localhost:8443/api"
echo "  User: admin / admin"
echo "  Header: X-Requested-With: OpenAPI"
echo ""
echo "Tools available: curl, nc, python3, vim, nano"
echo "======================================================="
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Maximize Firefox if open
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="