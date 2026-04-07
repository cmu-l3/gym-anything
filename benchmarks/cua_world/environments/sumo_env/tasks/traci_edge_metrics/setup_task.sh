#!/bin/bash
echo "=== Setting up traci_edge_metrics task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Ensure output directory exists and is clean
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/traci_monitor.py 2>/dev/null || true
rm -f /home/ga/SUMO_Output/edge_metrics.csv 2>/dev/null || true
chown -R ga:ga /home/ga/SUMO_Output

# Ensure traci is in PYTHONPATH for the ga user
if ! grep -q "PYTHONPATH.*/usr/share/sumo/tools" /home/ga/.bashrc; then
    echo 'export PYTHONPATH="/usr/share/sumo/tools:$PYTHONPATH"' >> /home/ga/.bashrc
    chown ga:ga /home/ga/.bashrc
fi

# Make sure terminal is open
if ! pgrep -f "terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 x-terminal-emulator &"
    sleep 3
fi

# Wait for terminal window and maximize it
wait_for_window "Terminal\|terminal" 10
focus_and_maximize "Terminal\|terminal"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="