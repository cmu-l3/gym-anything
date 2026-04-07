#!/bin/bash
echo "=== Setting up Command Acceptance Test Suite task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/test_report.json 2>/dev/null || true
rm -f /tmp/command_acceptance_test_suite_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/command_acceptance_test_suite_start_ts
echo "Task start recorded: $(cat /tmp/command_acceptance_test_suite_start_ts)"

# Function to get total INST commands safely
get_total_inst_cmds() {
    local total=0
    # Try querying the target overall count
    local target_total=$(cosmos_api "get_cmd_cnt" '"INST"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null)
    if [[ "$target_total" =~ ^[0-9]+$ ]] && [ "$target_total" -gt 0 ]; then
        echo "$target_total"
        return
    fi

    # Fallback: sum common INST commands from dictionary
    for cmd in COLLECT SETPARAMS CLEAR ABORT NOOP ROUTE IGNORE ENABLE DISABLE; do
        local cnt=$(cosmos_api "get_cmd_cnt" "\"INST\",\"$cmd\"" 2>/dev/null | jq -r '.result // 0' 2>/dev/null)
        if [[ "$cnt" =~ ^[0-9]+$ ]]; then
            total=$((total + cnt))
        fi
    done
    echo "$total"
}

INITIAL_CMD_COUNT=$(get_total_inst_cmds)
echo "Initial INST command count: $INITIAL_CMD_COUNT"
printf '%s' "$INITIAL_CMD_COUNT" > /tmp/command_acceptance_test_suite_initial_cmds

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
take_screenshot /tmp/command_acceptance_test_suite_start.png

echo "=== Setup Complete ==="
echo ""
echo "Task: Execute a command-response acceptance test suite."
echo "Output must be written to: /home/ga/Desktop/test_report.json"
echo ""