#!/bin/bash
echo "=== Setting up accessibility_visual_compliance task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Clean up previous artifacts to ensure fresh run
rm -f /home/ga/original_ui.png
rm -f /home/ga/process_accessibility.py
rm -f /home/ga/accessibility_proof_gray.png
rm -f /home/ga/luminance_report.txt

# Record initial OpenICE log size
LOG_FILE="/home/ga/openice/logs/openice.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
stat -c %s "$LOG_FILE" > /tmp/initial_log_size

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

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Artifacts cleaned. Initial windows: $INITIAL_WINDOWS"