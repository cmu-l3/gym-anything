#!/bin/bash
echo "=== Setting up generate_grid_network task ==="

# Record task start time for anti-gaming (ensures agent actually creates files)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Ensure SUMO environment variables are set globally
export SUMO_HOME="/usr/share/sumo"

# Clean up working directory if it exists, then recreate it
WORK_DIR="/home/ga/SUMO_Scenarios/grid_development"
rm -rf "$WORK_DIR"
su - ga -c "mkdir -p $WORK_DIR"

# Kill any existing SUMO processes
pkill -f "sumo-gui" 2>/dev/null || true
pkill -f "sumo " 2>/dev/null || true
pkill -f "netedit" 2>/dev/null || true
sleep 1

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory=$WORK_DIR &"
    sleep 3
fi

# Make sure terminal is focused and maximized
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== Task setup complete ==="
echo "Working directory prepared: $WORK_DIR"