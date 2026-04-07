#!/bin/bash
echo "=== Setting up infusion_interlock_oq_protocol task ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Delete stale outputs BEFORE recording timestamp
# ---------------------------------------------------------------
rm -f /home/ga/Desktop/oq_test_threshold.png
rm -f /home/ga/Desktop/oq_test_failsafe.png
rm -f /home/ga/Desktop/oq_test_results.csv
rm -f /home/ga/Desktop/oq_validation_report.txt
rm -f /tmp/task_result.json

# ---------------------------------------------------------------
# 2. Record task start timestamp (anti-gaming: after cleanup)
# ---------------------------------------------------------------
date +%s > /tmp/task_start_timestamp

# ---------------------------------------------------------------
# 3. Record initial OpenICE log size (only analyze NEW lines)
# ---------------------------------------------------------------
LOG_FILE="/home/ga/openice/logs/openice.log"
mkdir -p /home/ga/openice/logs
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# ---------------------------------------------------------------
# 4. Ensure OpenICE is running
# ---------------------------------------------------------------
ensure_openice_running

# Wait for the Supervisor window to appear
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected after 60s"
fi

# Focus and maximize the Supervisor
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ---------------------------------------------------------------
# 5. Record initial window count
# ---------------------------------------------------------------
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# ---------------------------------------------------------------
# 6. Take initial screenshot
# ---------------------------------------------------------------
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log offset: $LOG_SIZE bytes"
echo "Initial windows: $INITIAL_WINDOWS"
