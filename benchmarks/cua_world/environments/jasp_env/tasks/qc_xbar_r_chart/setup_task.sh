#!/bin/bash
set -e
echo "=== Setting up QC X-bar R Chart Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/JASP/qc_analysis.jasp
rm -f /home/ga/Documents/JASP/qc_report.txt

# Ensure the dataset exists
DATASET="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from backup..."
    cp "/opt/jasp_datasets/Big Five Personality Traits.csv" "$DATASET" 2>/dev/null || \
    cp "/opt/jasp_datasets/BigFivePersonalityTraits.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# Ensure JASP is not currently running
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP with the dataset
# We use setsid to detach from the shell so it survives when the setup script exits
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window to appear
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Small buffer to allow GUI to render
sleep 5

# Maximize the JASP window
echo "Maximizing JASP..."
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any potential "Check for Updates" or startup dialogs
# Press Escape a couple of times to be safe
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="