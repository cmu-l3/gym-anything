#!/bin/bash
echo "=== Setting up Conditional Contingency Procedure task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/conditional_pass_report.json 2>/dev/null || true
rm -f /tmp/conditional_contingency_procedure_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/conditional_contingency_procedure_start_ts
echo "Task start recorded: $(cat /tmp/conditional_contingency_procedure_start_ts)"

# Record initial command counts for both possible branches
INITIAL_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
INITIAL_ABORT=$(cosmos_api "get_cmd_cnt" '"INST","ABORT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial COLLECT count: $INITIAL_COLLECT"
echo "Initial ABORT count: $INITIAL_ABORT"
printf '%s' "$INITIAL_COLLECT" > /tmp/conditional_contingency_initial_collect
printf '%s' "$INITIAL_ABORT" > /tmp/conditional_contingency_initial_abort

# Randomly inject either a nominal or contingency thermal state
# This ensures the agent must dynamically evaluate the logic rather than hardcoding a path
RAND_VAL=$((RANDOM % 100))
if [ "$RAND_VAL" -gt 50 ]; then
    echo "Injecting CONTINGENCY state (TEMP1 > 55.0)..."
    cosmos_api "inject_tlm" '"INST","HEALTH_STATUS",{"TEMP1":58.5}' 2>/dev/null || true
else
    echo "Injecting NOMINAL state (TEMP1 < 55.0)..."
    cosmos_api "inject_tlm" '"INST","HEALTH_STATUS",{"TEMP1":42.0}' 2>/dev/null || true
fi
sleep 2

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
take_screenshot /tmp/conditional_contingency_procedure_start.png

echo "=== Conditional Contingency Procedure Setup Complete ==="
echo "Target output file: /home/ga/Desktop/conditional_pass_report.json"