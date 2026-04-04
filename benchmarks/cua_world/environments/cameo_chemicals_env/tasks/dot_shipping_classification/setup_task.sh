#!/bin/bash
# setup_task.sh - Pre-task hook for dot_shipping_classification
# Cleans workspace and launches CAMEO Chemicals

echo "=== Setting up DOT Shipping Classification Task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
# Ensure Desktop exists
mkdir -p /home/ga/Desktop
# Remove the target file if it exists to ensure fresh creation
rm -f /home/ga/Desktop/dot_shipping_report.txt
echo "Cleaned up previous report files."

# 3. Launch Application (Firefox to CAMEO Chemicals)
# Check if Firefox is already running
if ! pgrep -f firefox > /dev/null; then
    echo "Launching Firefox..."
    # Launch with specific profile and URL
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox_launch.log 2>&1 &"
    
    # Wait for process
    sleep 5
fi

# 4. Wait for Window and Maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Get Window ID
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')

if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
else
    echo "WARNING: Could not find Firefox window to maximize."
fi

# 5. Capture Initial State Screenshot (Evidence)
echo "Capturing initial screenshot..."
sleep 2 # Wait for render
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot capture
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Failed to capture initial screenshot."
fi

echo "=== Task Setup Complete ==="