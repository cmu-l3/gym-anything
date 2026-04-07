#!/bin/bash
echo "=== Setting up Fleeting Contact AOS Automation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start recorded: $(cat /tmp/task_start_time.txt)"

# Remove stale files to prevent false positives
rm -f /home/ga/Desktop/pass_capture.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/ready_for_pass.txt 2>/dev/null || true
rm -f /tmp/aos_start.txt 2>/dev/null || true
rm -f /tmp/aos_end.txt 2>/dev/null || true

# Explicitly disconnect the INST_INT interface to begin the scenario
echo "Disconnecting INST_INT interface..."
cosmos_api "disconnect_interface" '"INST_INT"' 2>/dev/null || true
sleep 2

# Record initial CMD_ACPT_CNT to verify the command was actually sent later
INITIAL_CMD_ACPT=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null | sed 's/"//g' || echo "0")
echo "Initial CMD_ACPT_CNT: $INITIAL_CMD_ACPT"
printf '%s' "$INITIAL_CMD_ACPT" > /tmp/initial_cmd_acpt.txt

# =====================================================================
# Create and launch the background simulation script
# =====================================================================
cat > /tmp/aos_sim.sh << 'EOF'
#!/bin/bash
source /workspace/scripts/task_utils.sh

# 1. Wait for the agent to signal they are ready
while [ ! -f /tmp/ready_for_pass.txt ]; do
    sleep 0.5
done

echo "Ready signal detected. Waiting random 5-15s before AOS..."

# 2. Wait a random time between 5 and 15 seconds
sleep $((5 + RANDOM % 11))

# 3. Trigger AOS (Connect interface)
echo "Triggering AOS..."
date +%s.%N > /tmp/aos_start.txt
cosmos_api "connect_interface" '"INST_INT"' 2>/dev/null || true

# 4. Keep window open for exactly 15 seconds
sleep 15

# 5. Trigger LOS (Disconnect interface)
echo "Triggering LOS..."
cosmos_api "disconnect_interface" '"INST_INT"' 2>/dev/null || true
date +%s.%N > /tmp/aos_end.txt
echo "Simulation complete."
EOF

chmod +x /tmp/aos_sim.sh
# Launch simulation in the background as user 'ga'
su - ga -c "nohup bash /tmp/aos_sim.sh > /tmp/aos_sim.log 2>&1 &"
echo "Background AOS simulation started."

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo ""
echo "Task: Wait for AOS, send command, record timestamps."
echo "Output must be written to: /home/ga/Desktop/pass_capture.json"
echo ""