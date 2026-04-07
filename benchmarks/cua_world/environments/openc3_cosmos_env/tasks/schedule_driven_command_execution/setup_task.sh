#!/bin/bash
echo "=== Setting up Schedule-Driven Command Execution task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files
rm -f /home/ga/Desktop/pass_executor.py 2>/dev/null || true
rm -f /home/ga/Desktop/execution_receipt.json 2>/dev/null || true
rm -f /home/ga/Documents/pass_schedule.csv 2>/dev/null || true
rm -f /tmp/schedule_driven_command_execution_result.json 2>/dev/null || true

# Generate the pass schedule CSV
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/pass_schedule.csv << 'EOF'
seq_id,time_offset,command_string
1,3,INST CLEAR
2,9,INST COLLECT with TYPE NORMAL, DURATION 2
3,16,INST COLLECT with TYPE SPECIAL, DURATION 4
4,22,INST ABORT
EOF
chown ga:ga /home/ga/Documents/pass_schedule.csv

# Record task start timestamp
date +%s > /tmp/schedule_driven_command_execution_start_ts
echo "Task start recorded: $(cat /tmp/schedule_driven_command_execution_start_ts)"

# Record initial command counts for verification
INIT_CLEAR=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
INIT_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
INIT_ABORT=$(cosmos_api "get_cmd_cnt" '"INST","ABORT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

echo "$INIT_CLEAR" > /tmp/schedule_driven_init_clear
echo "$INIT_COLLECT" > /tmp/schedule_driven_init_collect
echo "$INIT_ABORT" > /tmp/schedule_driven_init_abort

echo "Initial CMD Counts - CLEAR: $INIT_CLEAR, COLLECT: $INIT_COLLECT, ABORT: $INIT_ABORT"

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
take_screenshot /tmp/schedule_driven_command_execution_start.png

echo "=== Setup Complete ==="
echo ""
echo "Schedule written to: /home/ga/Documents/pass_schedule.csv"