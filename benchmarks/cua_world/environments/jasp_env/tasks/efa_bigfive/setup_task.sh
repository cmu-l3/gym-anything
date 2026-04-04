#!/bin/bash
echo "=== Setting up Exploratory Factor Analysis (EFA) Task ==="

# Source utilities (if available, otherwise define basics)
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define paths
JASP_DOCS="/home/ga/Documents/JASP"
DATASET="$JASP_DOCS/BigFivePersonalityTraits.csv"
OUTPUT_JASP="$JASP_DOCS/BigFive_EFA.jasp"
OUTPUT_REPORT="$JASP_DOCS/efa_report.txt"

# Clean up previous run artifacts
rm -f "$OUTPUT_JASP" 2>/dev/null || true
rm -f "$OUTPUT_REPORT" 2>/dev/null || true

# Ensure dataset exists and has correct permissions
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from source..."
    cp "/opt/jasp_datasets/Big Five Personality Traits.csv" "$DATASET" 2>/dev/null || \
    cp "/opt/jasp_datasets/BigFivePersonalityTraits.csv" "$DATASET" 2>/dev/null || \
    echo "ERROR: Dataset not found in /opt/jasp_datasets"
fi
chmod 644 "$DATASET"
chown ga:ga "$DATASET"

# Kill any existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Launch JASP (Empty state)
# We use setsid to detach from the shell so it survives
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Wait a bit for UI to settle
sleep 5

# Maximize JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss any potential welcome/update dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="