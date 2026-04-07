#!/bin/bash
echo "=== Setting up Sepsis Simulation Tuning Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp

# 2. Clean up artifacts from previous runs
rm -f /home/ga/Desktop/sepsis_vitals_evidence.png
rm -f /home/ga/Desktop/sepsis_config.json
rm -f /tmp/task_result.json

# 3. Record initial state of OpenICE
# We track log size to only analyze NEW log entries
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    stat -c %s "$LOG_FILE" > /tmp/initial_log_size
else
    echo "0" > /tmp/initial_log_size
fi

# 4. Ensure OpenICE is running
ensure_openice_running

# 5. Wait for and setup window
if wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "OpenICE window detected."
    focus_openice_window
    sleep 1
    # Maximize for visibility
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
else
    echo "WARNING: OpenICE window not found during setup."
fi

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="