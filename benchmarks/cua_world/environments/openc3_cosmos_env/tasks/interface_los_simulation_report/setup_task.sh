#!/bin/bash
echo "=== Setting up Interface LOS Simulation task ==="

source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Record task start timestamp
date +%s > /tmp/task_start_ts
echo "Task start recorded: $(cat /tmp/task_start_ts)"

# Remove stale output files
rm -f /home/ga/Desktop/los_event_report.json 2>/dev/null || true
rm -f /tmp/los_simulation_result.json 2>/dev/null || true

# Setup Ground Truth Monitor
echo "Starting background state monitor..."
mkdir -p /var/lib/app/ground_truth
chmod 700 /var/lib/app/ground_truth
rm -f /var/lib/app/ground_truth/iface_history.log

cat > /var/lib/app/ground_truth/monitor.sh << 'EOF'
#!/bin/bash
OPENC3_URL="http://localhost:2900"
TOKEN=$(cat /home/ga/.cosmos_token 2>/dev/null || echo "Cosmos2024!")
LOG="/var/lib/app/ground_truth/iface_history.log"

echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") MONITOR_STARTED" > "$LOG"

PREV_STATE="UNKNOWN"
while true; do
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    RESP=$(curl -s -m 2 -X POST "$OPENC3_URL/openc3-api/api" \
        -H "Content-Type: application/json" \
        -H "Authorization: $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"get_interfaces","params":[],"id":1,"keyword_params":{"scope":"DEFAULT"}}')
    
    STATE=$(echo "$RESP" | jq -r '.result[] | select(.name == "INST_INT") | .state' 2>/dev/null)
    
    if [ -z "$STATE" ] || [ "$STATE" == "null" ]; then
        STATE="ERROR_OR_MISSING"
    fi

    if [ "$STATE" != "$PREV_STATE" ]; then
        echo "$TS $STATE" >> "$LOG"
        PREV_STATE="$STATE"
    fi
    sleep 1
done
EOF

chmod +x /var/lib/app/ground_truth/monitor.sh
nohup /var/lib/app/ground_truth/monitor.sh > /dev/null 2>&1 &
echo $! > /var/lib/app/ground_truth/monitor.pid

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
take_screenshot /tmp/los_simulation_start.png

echo "=== Interface LOS Simulation Setup Complete ==="
echo ""
echo "Task: Simulate a network dropout and report timestamps."
echo "Output must be written to: /home/ga/Desktop/los_event_report.json"
echo ""