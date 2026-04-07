#!/bin/bash
set -e
echo "=== Setting up EHR Integration Feasibility Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_timestamp.txt

# 2. ensure clean state for report file
rm -f /home/ga/Desktop/ehr_integration_report.txt

# 3. Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window to be fully ready
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 4. Record initial log size (to check ONLY new log lines later)
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log directory exists
mkdir -p $(dirname "$LOG_FILE")
touch "$LOG_FILE"
# Get current size in bytes
stat -c %s "$LOG_FILE" > /tmp/initial_log_size.txt
echo "Initial log size recorded: $(cat /tmp/initial_log_size.txt)"

# 5. Record initial window list (to detect new device windows)
DISPLAY=:1 wmctrl -l > /tmp/initial_windows.txt

# 6. Ensure source code is accessible for investigation
if [ -d "/opt/openice/mdpnp" ]; then
    echo "Source code verified at /opt/openice/mdpnp"
else
    echo "Warning: Source code directory not found at standard location"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="