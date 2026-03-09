#!/bin/bash
set -e
echo "=== Setting up process_capability_tooth_growth task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists in Documents (using the copy from setup_jasp.sh)
DATA_SRC="/home/ga/Documents/JASP/ToothGrowth.csv"
if [ ! -f "$DATA_SRC" ]; then
    echo "Restoring ToothGrowth.csv..."
    cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATA_SRC"
    chown ga:ga "$DATA_SRC"
fi

# 3. Clean previous results
rm -f /home/ga/Documents/JASP/capability_analysis.jasp
rm -f /home/ga/Documents/JASP/cpk_report.txt

# 4. Start JASP (clean state, no dataset loaded initially, let agent load it)
# We use the launcher script which handles setsid and flags
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    su - ga -c "setsid /usr/local/bin/launch-jasp > /dev/null 2>&1 &"
    
    # Wait for JASP window
    echo "Waiting for JASP window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize and Focus
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="