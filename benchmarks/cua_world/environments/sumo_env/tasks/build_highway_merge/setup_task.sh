#!/bin/bash
echo "=== Setting up build_highway_merge task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean any existing artifacts and create a clean environment
rm -rf /home/ga/SUMO_Output/highway_merge
mkdir -p /home/ga/SUMO_Output/highway_merge
chown -R ga:ga /home/ga/SUMO_Output

# Open a terminal for the agent in the working directory
if command -v gnome-terminal &> /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Output/highway_merge &"
elif command -v xfce4-terminal &> /dev/null; then
    su - ga -c "DISPLAY=:1 xfce4-terminal --working-directory=/home/ga/SUMO_Output/highway_merge &"
else
    su - ga -c "DISPLAY=:1 xterm -cd /home/ga/SUMO_Output/highway_merge &"
fi

# Wait for terminal window to launch
sleep 3
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot demonstrating the starting clean state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="