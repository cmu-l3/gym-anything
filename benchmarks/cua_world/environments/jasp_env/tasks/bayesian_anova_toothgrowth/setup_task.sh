#!/bin/bash
set -e
echo "=== Setting up Bayesian ANOVA task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running JASP instances to ensure clean state
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

# Ensure the dataset exists and has correct permissions
DATASET="/home/ga/Documents/JASP/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from /opt/jasp_datasets..."
    mkdir -p /home/ga/Documents/JASP
    cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET" 2>/dev/null || cp "/opt/jasp_datasets/ToothGrowth.csv" "$DATASET"
    chown ga:ga "$DATASET"
    chmod 644 "$DATASET"
fi

# Clean up any previous run artifacts
rm -f "/home/ga/Documents/JASP/ToothGrowth_BayesianANOVA.jasp"
rm -f "/home/ga/Documents/JASP/bayesian_anova_results.txt"

echo "Dataset ready: $DATASET"

# Launch JASP with the dataset
# CRITICAL: Use the system-wide launcher wrapper which handles sandboxing and display
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

# Wait a bit for the interface to fully load
sleep 5

# Maximize the JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (e.g., welcome screen or updates) if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="