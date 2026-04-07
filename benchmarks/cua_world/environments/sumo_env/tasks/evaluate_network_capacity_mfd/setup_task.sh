#!/bin/bash
echo "=== Setting up evaluate_network_capacity_mfd task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean slate for SUMO processes
echo "Killing any existing SUMO processes..."
pkill -f "sumo-gui" 2>/dev/null || true
pkill -f "sumo " 2>/dev/null || true
sleep 1

# Clean and prepare output directory
echo "Preparing output directory..."
rm -rf /home/ga/SUMO_Output/* 2>/dev/null || true
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Make sure Pasubio scenario is ready and owned by user
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio/

# Start a terminal window for the agent since this is a CLI workflow
if ! pgrep -f "terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 x-terminal-emulator --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Try to maximize the terminal for better visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="