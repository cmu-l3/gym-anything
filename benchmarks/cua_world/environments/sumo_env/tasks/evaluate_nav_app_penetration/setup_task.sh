#!/bin/bash
echo "=== Setting up evaluate_nav_app_penetration task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create clean output directory
sudo -u ga mkdir -p /home/ga/SUMO_Output
sudo -u ga rm -f /home/ga/SUMO_Output/*.xml 2>/dev/null || true
sudo -u ga rm -f /home/ga/SUMO_Output/*.csv 2>/dev/null || true

# Start a terminal for the agent to use
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Focus and maximize the terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
fi

echo "=== Task setup complete ==="