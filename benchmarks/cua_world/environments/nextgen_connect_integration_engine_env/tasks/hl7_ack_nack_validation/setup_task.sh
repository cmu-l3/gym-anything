#!/bin/bash
echo "=== Setting up HL7 ACK/NACK Validation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Ensure port 6661 is free (kill anything using it)
fuser -k 6661/tcp 2>/dev/null || true

# Clean up output directory
rm -rf /home/ga/hl7_outbound
mkdir -p /home/ga/hl7_outbound
chown ga:ga /home/ga/hl7_outbound

# Wait for NextGen Connect API to be ready
echo "Waiting for NextGen Connect API..."
wait_for_api 60

# Check if channel already exists and delete it if so (ensure clean slate)
EXISTING_ID=$(get_channel_id "ADT_Inbound_Validator")
if [ -n "$EXISTING_ID" ]; then
    echo "Removing existing channel $EXISTING_ID..."
    api_call_json DELETE "/channels/$EXISTING_ID" > /dev/null
    # Need to deploy the deletion to stop the channel
    api_call_json POST "/channels/_redeployAll" > /dev/null
fi

# Ensure Firefox is showing dashboard
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:8443' &"
    sleep 10
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open a terminal with helper info
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " TASK: HL7 ACK/NACK Validation Channel"
echo "======================================================="
echo ""
echo "Goal: Create channel \"ADT_Inbound_Validator\" on Port 6661"
echo ""
echo "Requirements:"
echo "1. Source: TCP Listener (MLLP) on port 6661"
echo "2. Validation:"
echo "   - IF PID.3 AND PID.5 present -> Reply ACK (AA)"
echo "   - IF PID.3 OR PID.5 missing  -> Reply NACK (AE)"
echo "3. Destination: Write to /home/ga/hl7_outbound/"
echo ""
echo "API Info:"
echo "- URL: https://localhost:8443/api"
echo "- User: admin / admin"
echo "- Header: X-Requested-With: OpenAPI"
echo ""
echo "Useful Commands:"
echo "  netcat/nc: Send test messages to localhost 6661"
echo "  curl: Interact with API"
echo "======================================================="
exec bash
' 2>/dev/null &

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="