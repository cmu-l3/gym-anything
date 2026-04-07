#!/bin/bash
echo "=== Setting up Clinical Data ETL Pipeline task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (for anti-gaming and log filtering)
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded."

# 2. Prepare Log File Tracking
# We record the initial size so we only verify data generated *during* this session
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ ! -f "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
fi
stat -c %s "$LOG_FILE" > /tmp/initial_log_size
echo "Initial log size recorded."

# 3. Clean Environment
# Remove the target output file if it exists to ensure fresh creation
rm -f "/home/ga/Desktop/vital_signs_dataset.csv"

# 4. Ensure OpenICE is Running
# The task requires the user to interact with the GUI to generate data
ensure_openice_running

# 5. Wait for UI to be ready
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# 6. Maximize Window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Target: Generate data and extract to /home/ga/Desktop/vital_signs_dataset.csv"