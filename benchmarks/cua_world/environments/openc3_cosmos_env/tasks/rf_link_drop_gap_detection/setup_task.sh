#!/bin/bash
echo "=== Setting up RF Link Drop Gap Detection task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Clean up stale files
rm -f /home/ga/Desktop/gap_report.json 2>/dev/null || true
rm -f /tmp/rf_link_drop_gap_detection_result.json 2>/dev/null || true
rm -f /tmp/actual_drop_duration.txt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start recorded: $(cat /tmp/task_start_time.txt)"

# Create the simulator script on the Desktop
cat > /home/ga/Desktop/simulate_link_drop.sh << 'EOF'
#!/bin/bash
echo "=== RF Link Drop Simulator ==="
echo "Generating randomized drop duration..."

# Generate a random duration between 4.0 and 9.0 seconds
DROP_DUR=$(awk -v min=4.0 -v max=9.0 'BEGIN{srand(); printf "%.2f\n", min+rand()*(max-min)}')
echo "$DROP_DUR" > /tmp/actual_drop_duration.txt

TOKEN=$(cat /home/ga/.cosmos_token 2>/dev/null || echo "Cosmos2024!")

echo "Disconnecting INST_INT interface..."
curl -s -X POST "http://localhost:2900/openc3-api/api" \
    -H "Content-Type: application/json" \
    -H "Authorization: $TOKEN" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"disconnect_interface\",\"params\":[\"INST_INT\"],\"id\":1,\"keyword_params\":{\"scope\":\"DEFAULT\"}}" > /dev/null

echo "Link dropped. Waiting for $DROP_DUR seconds..."
sleep $DROP_DUR

echo "Reconnecting INST_INT interface..."
curl -s -X POST "http://localhost:2900/openc3-api/api" \
    -H "Content-Type: application/json" \
    -H "Authorization: $TOKEN" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"connect_interface\",\"params\":[\"INST_INT\"],\"id\":1,\"keyword_params\":{\"scope\":\"DEFAULT\"}}" > /dev/null

echo "RF link restored."
EOF

# Set permissions
chmod +x /home/ga/Desktop/simulate_link_drop.sh
chown ga:ga /home/ga/Desktop/simulate_link_drop.sh

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
take_screenshot /tmp/rf_link_drop_start.png

echo "=== Setup Complete ==="
echo "Simulator placed at: /home/ga/Desktop/simulate_link_drop.sh"