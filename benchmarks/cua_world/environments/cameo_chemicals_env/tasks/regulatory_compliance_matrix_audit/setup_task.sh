#!/bin/bash
# setup_task.sh - Pre-task hook for regulatory_compliance_matrix_audit

set -e
echo "=== Setting up regulatory_compliance_matrix_audit task ==="

# Source utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Clean up previous artifacts (CRITICAL for valid verification)
rm -f /home/ga/Desktop/compliance_matrix.csv
echo "Cleaned up previous compliance_matrix.csv"

# Kill any existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process
echo "Waiting for Firefox process..."
for i in {1..30}; do
    if pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox process started."
        break
    fi
    sleep 1
done

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Allow page to load
sleep 5

# Maximize Firefox window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Maximizing window $WINDOW_ID"
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot captured."

echo "=== Task setup complete ==="