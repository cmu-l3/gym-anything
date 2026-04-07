#!/bin/bash
echo "=== Setting up checkpoint_peak_congestion_state task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes to ensure a clean slate
kill_sumo
sleep 1

# Ensure a fresh output directory exists
mkdir -p /home/ga/SUMO_Output
rm -rf /home/ga/SUMO_Output/*
chown -R ga:ga /home/ga/SUMO_Output

# Start a terminal for the user (since it's a CLI-heavy task)
if command -v gnome-terminal &> /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga >/dev/null 2>&1 &"
elif command -v x-terminal-emulator &> /dev/null; then
    su - ga -c "DISPLAY=:1 x-terminal-emulator >/dev/null 2>&1 &"
else
    su - ga -c "DISPLAY=:1 xterm >/dev/null 2>&1 &"
fi

# Wait for terminal to appear
sleep 3
wait_for_window "Terminal\|xterm\|ga@" 10

# Focus and maximize terminal
focus_and_maximize "Terminal\|xterm\|ga@"
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="