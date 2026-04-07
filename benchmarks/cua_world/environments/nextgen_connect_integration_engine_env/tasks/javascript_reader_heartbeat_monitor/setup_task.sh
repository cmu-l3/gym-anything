#!/bin/bash
echo "=== Setting up Heartbeat Monitor Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Ensure the output directory does NOT exist (agent must handle creation)
if [ -d "/opt/heartbeat_output" ]; then
    echo "Cleaning up existing output directory..."
    rm -rf /opt/heartbeat_output
fi

# Ensure NextGen Connect is running
echo "Checking NextGen Connect status..."
wait_for_api 120 || echo "Warning: API not fully ready yet"

# Open a terminal window for the agent with instructions
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " NextGen Connect - Heartbeat Monitor Task"
echo "======================================================="
echo ""
echo "GOAL: Create a heartbeat channel."
echo ""
echo "Specs:"
echo "  1. Channel Name: Heartbeat_Monitor"
echo "  2. Source: JavaScript Reader"
echo "     - Polling Interval: 15 seconds (15000 ms)"
echo "     - Content: HL7 v2.5 ADT^A01 message"
echo "     - MSH-3 (Sending App): HEARTBEAT_MONITOR"
echo "     - PID-3 (Patient ID): HEARTBEAT001"
echo "  3. Destination: File Writer"
echo "     - Directory: /opt/heartbeat_output/"
echo "     - Filename: Unique (e.g., timestamp based)"
echo ""
echo "  4. ACTION: Deploy the channel and verify output files."
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Header: X-Requested-With: OpenAPI"
echo ""
echo "Useful Code Snippet (JS Reader):"
echo "  return \"MSH|^~\\\\&|HEARTBEAT_MONITOR|...\\rEVN|...\\rPID|...\""
echo ""
exec bash
' 2>/dev/null &

# Focus the terminal
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="