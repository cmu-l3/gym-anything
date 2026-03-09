#!/bin/bash
# setup_task.sh - Pre-task hook for nfpa_30_flammable_liquid_classification

echo "=== Setting up NFPA 30 Classification Task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Prepare environment
# Clean up any previous run artifacts
rm -f /home/ga/Documents/flammable_liquid_classes.csv 2>/dev/null || true
# Ensure directory exists
mkdir -p /home/ga/Documents/

# 3. Start Application (Firefox)
# We start Firefox pointing to CAMEO Chemicals to ensure a consistent starting state
echo "Starting Firefox..."
kill_firefox "ga" 2>/dev/null || true

# Launch Firefox
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# 4. Wait for window and maximize
# Wait for the window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Get Window ID
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')

if [ -n "$WID" ]; then
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus the window
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    echo "Firefox window maximized and focused."
else
    echo "WARNING: Could not find Firefox window to maximize."
fi

# 5. Take initial screenshot (Evidence)
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot taken."

echo "=== Task setup complete ==="