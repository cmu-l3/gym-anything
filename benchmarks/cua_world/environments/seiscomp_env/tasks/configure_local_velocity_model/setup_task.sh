#!/bin/bash
echo "=== Setting up configure_local_velocity_model task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/seiscomp/share/locsat/tables
mkdir -p /home/ga/seiscomp/etc
mkdir -p /home/ga/.seiscomp

# Remove any existing GYM_LOCAL files to ensure a clean starting state
rm -f /home/ga/seiscomp/share/locsat/tables/GYM_LOCAL.*

# Remove any existing configuration references to GYM_LOCAL
find /home/ga/seiscomp/etc /home/ga/.seiscomp -name "*.cfg" -type f -exec sed -i '/GYM_LOCAL/d' {} + 2>/dev/null || true

# Fix permissions
chown -R ga:ga /home/ga/seiscomp/share/locsat
chown -R ga:ga /home/ga/.seiscomp

# Open a terminal window for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 3
fi

# Try to maximize the active terminal window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take an initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="