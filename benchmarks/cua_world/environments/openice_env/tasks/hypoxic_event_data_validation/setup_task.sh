#!/bin/bash
echo "=== Setting up Hypoxic Event Data Validation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming (file creation checks)
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size (to verify new actions only)
LOG_FILE="/home/ga/openice/logs/openice.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE Supervisor is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any previous target files on Desktop
rm -f /home/ga/Desktop/hypoxia_test_data.csv 2>/dev/null || true

# Record initial window list
DISPLAY=:1 wmctrl -l > /tmp/initial_windows.txt

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Target file removed: /home/ga/Desktop/hypoxia_test_data.csv"
echo "Log size recorded: $LOG_SIZE"