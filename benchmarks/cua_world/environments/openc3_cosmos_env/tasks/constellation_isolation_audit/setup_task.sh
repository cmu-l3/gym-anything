#!/bin/bash
echo "=== Setting up Constellation Isolation Audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp) to prevent false positives
rm -f /home/ga/Desktop/isolation_audit.json 2>/dev/null || true
rm -f /tmp/constellation_isolation_audit_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/isolation_audit_start_ts
echo "Task start recorded: $(cat /tmp/isolation_audit_start_ts)"

# Record initial COLLECTS value for BOTH targets for anti-gaming verification
INST_INITIAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
INST2_INITIAL_COLLECTS=$(cosmos_tlm "INST2 HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")

echo "Pre-task INST COLLECTS: $INST_INITIAL_COLLECTS"
echo "Pre-task INST2 COLLECTS: $INST2_INITIAL_COLLECTS"

printf '%s' "$INST_INITIAL_COLLECTS" > /tmp/isolation_audit_inst_initial
printf '%s' "$INST2_INITIAL_COLLECTS" > /tmp/isolation_audit_inst2_initial

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
take_screenshot /tmp/isolation_audit_start.png

echo "=== Constellation Isolation Audit Setup Complete ==="
echo ""
echo "Task: Perform a bidirectional isolation check between INST and INST2."
echo "Output must be written to: /home/ga/Desktop/isolation_audit.json"
echo ""