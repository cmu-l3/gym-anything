#!/bin/bash
echo "=== Setting up Command Uplink Optimization task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/raw_schedule.csv 2>/dev/null || true
rm -f /home/ga/Desktop/optimized_schedule.json 2>/dev/null || true
rm -f /tmp/command_uplink_optimization_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/command_uplink_optimization_start_ts
echo "Task start recorded: $(cat /tmp/command_uplink_optimization_start_ts)"

# Record initial command and telemetry counts for the precise delta verification
INITIAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
INITIAL_CMD=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

echo "Initial COLLECTS telemetry: $INITIAL_COLLECTS"
echo "Initial COLLECT command count: $INITIAL_CMD"

printf '%s' "$INITIAL_COLLECTS" > /tmp/command_uplink_optimization_initial_collects
printf '%s' "$INITIAL_CMD" > /tmp/command_uplink_optimization_initial_cmd

# Create the raw schedule CSV
cat > /home/ga/Desktop/raw_schedule.csv << 'EOF'
seq_id,target,command,type,duration
1,INST,COLLECT,NORMAL,1.0
2,INST,COLLECT,NORMAL,1.0
3,INST,COLLECT,NORMAL,1.0
4,INST,COLLECT,NORMAL,2.0
5,INST,COLLECT,NORMAL,2.0
6,INST,COLLECT,NORMAL,3.0
7,INST,COLLECT,NORMAL,1.0
8,INST,COLLECT,NORMAL,1.0
EOF
chown ga:ga /home/ga/Desktop/raw_schedule.csv

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
take_screenshot /tmp/command_uplink_optimization_start.png

echo "=== Setup Complete ==="
echo "Raw schedule written to: /home/ga/Desktop/raw_schedule.csv"
echo ""