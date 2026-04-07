#!/bin/bash
echo "=== Setting up analyze_transit_stop_utilization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
sudo -u ga mkdir -p /home/ga/SUMO_Output
sudo -u ga rm -f /home/ga/SUMO_Output/stopinfos.xml
sudo -u ga rm -f /home/ga/SUMO_Output/utilization_report.txt

# Start a terminal for the user in the correct directory
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Wait for terminal window to appear
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Terminal"; then
        break
    fi
    sleep 1
done

# Maximize and focus the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
sleep 1
take_screenshot /tmp/task_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="