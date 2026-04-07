#!/bin/bash
echo "=== Setting up generate_waveform_availability_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the reports directory
su - ga -c "mkdir -p /home/ga/reports"

# Ensure clean state (remove any existing report)
rm -f /home/ga/reports/waveform_manifest.csv 2>/dev/null

# Ensure SeisComP environment is ready
ensure_scmaster_running

# Launch a terminal for the agent to use
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Focus the terminal
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot of the starting state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="