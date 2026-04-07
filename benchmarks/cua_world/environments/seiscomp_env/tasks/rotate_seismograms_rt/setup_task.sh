#!/bin/bash
echo "=== Setting up Rotate Seismograms Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP master and MariaDB are running
echo "Ensuring SeisComP services are running..."
ensure_scmaster_running

# Clean up any potential artifacts from previous runs
rm -f /home/ga/baz_toli.txt 2>/dev/null || true
rm -f /home/ga/rotation_plot.png 2>/dev/null || true
rm -f /home/ga/rotate_waveforms.py 2>/dev/null || true

# Ensure matplotlib is installed system-wide as a convenience, 
# though the agent is instructed they can install what they need
if ! dpkg -s python3-matplotlib >/dev/null 2>&1; then
    echo "Installing matplotlib for visualization..."
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install -y python3-matplotlib >/dev/null 2>&1 || true
fi

# Open a terminal for the agent to start working
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="