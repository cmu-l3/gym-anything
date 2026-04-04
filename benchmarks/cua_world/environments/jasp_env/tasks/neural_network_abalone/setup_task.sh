#!/bin/bash
set -e
echo "=== Setting up neural_network_abalone task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/JASP/Abalone_NeuralNet.jasp
rm -f /home/ga/Documents/JASP/abalone.csv
rm -f /home/ga/Documents/JASP/abalone_performance.txt

# Ensure JASP is running
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    # Launch JASP (using the launcher script that sets flags)
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected."
            break
        fi
        sleep 1
    done
    sleep 5
else
    echo "JASP is already running."
fi

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss any startup dialogs (Welcome screen, etc.)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="