#!/bin/bash
echo "=== Setting up generate_event_map_python task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP services are running
ensure_scmaster_running

# Make sure matplotlib is NOT installed (force the agent to install it)
echo "Removing python3-matplotlib if present..."
sudo apt-get remove -y python3-matplotlib 2>/dev/null || true
sudo apt-get autoremove -y 2>/dev/null || true

# Clean up any pre-existing files
rm -f /home/ga/noto_event_map.png 2>/dev/null || true
rm -f /home/ga/plot_event_map.py 2>/dev/null || true

# Open a terminal for the agent
echo "Starting terminal..."
if ! pgrep -f "x-terminal-emulator" > /dev/null; then
    su - ga -c "DISPLAY=:1 x-terminal-emulator > /dev/null 2>&1 &"
    sleep 3
fi

# Maximize the terminal window
focus_and_maximize "Terminal" || focus_and_maximize "ga@ubuntu"

# Allow UI to stabilize
sleep 2

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="