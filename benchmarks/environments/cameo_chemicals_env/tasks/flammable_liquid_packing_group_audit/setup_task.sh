#!/bin/bash
# setup_task.sh - Pre-task hook for flammable_liquid_packing_group_audit

echo "=== Setting up Flammable Liquid Packing Group Audit ==="

# Source utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback if utils not found
    function take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous run artifacts (ANTI-GAMING)
rm -f /home/ga/Documents/packing_group_audit.csv 2>/dev/null || true

# Kill any existing Firefox instances
echo "Killing existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox to start and window to appear
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Sleep to allow page load
sleep 5

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="