#!/bin/bash
echo "=== Setting up HL7 Latency Monitoring Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -rf /home/ga/latency_high
rm -rf /home/ga/latency_normal
mkdir -p /home/ga/latency_high
mkdir -p /home/ga/latency_normal
chown -R ga:ga /home/ga/latency_high /home/ga/latency_normal

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Ensure NextGen Connect is running
wait_for_api 10

# Open a terminal window for the agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "======================================================="
echo " NextGen Connect - Latency Based Routing Task"
echo "======================================================="
echo ""
echo "GOAL: Create channel \"Latency_Monitor\" on port 6661."
echo ""
echo "LOGIC:"
echo "  Calculate: Latency = (MSH-7) - (EVN-2)"
echo "  If Latency > 10 mins -> Write to /home/ga/latency_high/"
echo "  If Latency <= 10 mins -> Write to /home/ga/latency_normal/"
echo ""
echo "API: https://localhost:8443/api (admin/admin)"
echo "     Header: X-Requested-With: OpenAPI"
echo ""
echo "Tools available: curl, python3, javascript (in Mirth)"
echo "======================================================="
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="