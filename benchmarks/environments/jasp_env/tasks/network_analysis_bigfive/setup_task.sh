#!/bin/bash
set -e
echo "=== Setting up network_analysis_bigfive task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists in the user's documents
DATA_SRC="/opt/jasp_datasets/Big Five Personality Traits.csv"
DATA_DEST="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

mkdir -p /home/ga/Documents/JASP

if [ -f "$DATA_SRC" ]; then
    cp "$DATA_SRC" "$DATA_DEST"
    chown ga:ga "$DATA_DEST"
    chmod 644 "$DATA_DEST"
    echo "Dataset prepared at $DATA_DEST"
else
    echo "ERROR: Source dataset not found at $DATA_SRC"
    exit 1
fi

# Ensure JASP is running (start empty)
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    # Launch without a specific file to start empty
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for JASP to appear
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Dismiss any startup dialogs/welcome screens if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize JASP window
echo "Maximizing JASP window..."
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Clean up previous outputs if they exist
rm -f "/home/ga/Documents/JASP/BigFiveNetwork.jasp"
rm -f "/home/ga/Documents/JASP/network_report.txt"

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="