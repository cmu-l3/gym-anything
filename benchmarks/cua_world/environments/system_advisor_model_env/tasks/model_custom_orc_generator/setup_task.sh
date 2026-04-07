#!/bin/bash
echo "=== Setting up model_custom_orc_generator task ==="

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# Create project directory
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/orc_* 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Check if SAM is running, if not, try to start it, else just ensure it's maximized
if ! pgrep -f "sam" > /dev/null; then
    if [ -f "/opt/SAM/current/sam" ]; then
        su - ga -c "DISPLAY=:1 /opt/SAM/current/sam &"
        sleep 5
    fi
fi

# Maximize SAM window if present
DISPLAY=:1 wmctrl -r "System Advisor Model" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "System Advisor Model" 2>/dev/null || true

# Ensure a terminal is available for the agent (for Python scripting if they choose PySAM)
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Dismiss any popup dialogs that might block the agent
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="