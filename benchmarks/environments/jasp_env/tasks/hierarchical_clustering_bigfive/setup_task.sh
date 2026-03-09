#!/bin/bash
set -e
echo "=== Setting up Hierarchical Clustering task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -f /home/ga/Documents/JASP/HierarchicalClustering_BigFive.jasp 2>/dev/null || true
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Verify dataset exists
DATASET="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
if [ ! -f "$DATASET" ]; then
    echo "ERROR: BigFivePersonalityTraits.csv not found at $DATASET"
    # Fallback copy if missing (should be handled by env setup, but safe to have)
    if [ -f "/opt/jasp_datasets/Big Five Personality Traits.csv" ]; then
        cp "/opt/jasp_datasets/Big Five Personality Traits.csv" "$DATASET"
        chown ga:ga "$DATASET"
    else
        exit 1
    fi
fi

# Launch JASP with the dataset loaded
# Using setsid to ensure it survives shell exit and su for correct user
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "JASP|BigFive" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize the window
JASP_WIN=$(DISPLAY=:1 wmctrl -l | grep -iE "JASP|BigFive" | head -1 | awk '{print $1}')
if [ -n "$JASP_WIN" ]; then
    DISPLAY=:1 wmctrl -i -r "$JASP_WIN" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$JASP_WIN" 2>/dev/null || true
fi

# Dismiss any startup dialogs/popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="