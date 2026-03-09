#!/bin/bash
set -e
echo "=== Setting up Bayesian RM ANOVA Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists in the user's Documents
DATA_SRC="/opt/jasp_datasets/Big Five Personality Traits.csv"
DATA_DEST="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
mkdir -p "$(dirname "$DATA_DEST")"

if [ ! -f "$DATA_DEST" ]; then
    if [ -f "$DATA_SRC" ]; then
        echo "Copying dataset..."
        cp "$DATA_SRC" "$DATA_DEST"
        chown ga:ga "$DATA_DEST"
    else
        echo "ERROR: Source dataset not found at $DATA_SRC"
        exit 1
    fi
fi

# Start JASP
# Use setsid to ensure it survives shell exit, and proper flags for the environment
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss any startup dialogs (Welcome screen, etc.)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="