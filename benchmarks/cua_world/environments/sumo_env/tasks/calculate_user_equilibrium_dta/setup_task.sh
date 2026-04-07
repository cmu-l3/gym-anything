#!/bin/bash
echo "=== Setting up calculate_user_equilibrium_dta task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure SUMO base output directory exists and clean target directory
sudo -u ga mkdir -p /home/ga/SUMO_Output
sudo -u ga rm -rf /home/ga/SUMO_Output/dta_study 2>/dev/null || true

# Ensure no stale background processes from previous tasks
pkill -f "gnome-terminal" 2>/dev/null || true
pkill -f "duaIterate" 2>/dev/null || true

# Open a terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Output &"
    sleep 3
fi

# Maximize the active window (terminal)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true

# Give the UI a moment to settle
sleep 1

# Take initial screenshot showing the clean terminal
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured successfully."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== Task setup complete ==="