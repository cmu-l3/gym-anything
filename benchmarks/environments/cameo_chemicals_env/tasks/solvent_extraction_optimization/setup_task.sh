#!/bin/bash
# setup_task.sh - Pre-task hook for solvent_extraction_optimization

echo "=== Setting up solvent_extraction_optimization task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove previous report if it exists (anti-gaming)
rm -f /home/ga/Documents/solvent_selection_report.txt

# Kill any existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process
for i in {1..30}; do
    if pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox process detected."
        break
    fi
    sleep 1
done

# Wait for window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Let the page load
sleep 5

# Maximize the window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Window maximized."
fi

# Dismiss any potential "Restore Session" or "Default Browser" dialogs (just in case)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="