#!/bin/bash
echo "=== Setting up Operating Room Turnover Simulation ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any existing artifacts
rm -f /home/ga/Desktop/turnover_log.txt 2>/dev/null || true
rm -f /tmp/window_history.log 2>/dev/null || true

# Start background Window Poller
# This records the state of windows every 2 seconds to verify the SEQUENCE of actions
# (Setup A -> Cleanup -> Setup B)
cat > /tmp/window_poller.sh << 'EOF'
#!/bin/bash
while true; do
    TS=$(date +%s)
    echo "--- TIMEFRAME $TS ---" >> /tmp/window_history.log
    DISPLAY=:1 wmctrl -l >> /tmp/window_history.log
    sleep 2
done
EOF

chmod +x /tmp/window_poller.sh
nohup /tmp/window_poller.sh > /dev/null 2>&1 &
POLLER_PID=$!
echo "$POLLER_PID" > /tmp/poller_pid.txt
echo "Window poller started with PID $POLLER_PID"

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Perform OR Turnover (Setup Case A -> Clear All -> Setup Case B)"