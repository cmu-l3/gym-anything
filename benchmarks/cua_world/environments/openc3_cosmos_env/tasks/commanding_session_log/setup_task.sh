#!/bin/bash
echo "=== Setting up Commanding Session Log task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/commanding_log.json 2>/dev/null || true
rm -f /tmp/commanding_session_log_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/commanding_session_log_start_ts
echo "Task start recorded: $(cat /tmp/commanding_session_log_start_ts)"

# Record initial command counts via API (for anti-gaming checks)
INITIAL_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
INITIAL_CLEAR=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
INITIAL_ABORT=$(cosmos_api "get_cmd_cnt" '"INST","ABORT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

echo "Initial COLLECT count: $INITIAL_COLLECT"
echo "Initial CLEAR count: $INITIAL_CLEAR"
echo "Initial ABORT count: $INITIAL_ABORT"

cat > /tmp/initial_cmd_counts.json << EOF
{
    "collect": $INITIAL_COLLECT,
    "clear": $INITIAL_CLEAR,
    "abort": $INITIAL_ABORT
}
EOF

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
take_screenshot /tmp/commanding_session_log_start.png

echo "=== Commanding Session Log Setup Complete ==="
echo ""
echo "Task: Send exactly 4 commands, read telemetry, and log the results."
echo "Output must be written to: /home/ga/Desktop/commanding_log.json"
echo ""