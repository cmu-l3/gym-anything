#!/bin/bash
set -e
echo "=== Setting up anova_planned_contrasts_viagra task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Ensure the dataset exists in the user's documents
DATASET_SOURCE="/opt/jasp_datasets/Viagra.csv"
DATASET_DEST="/home/ga/Documents/JASP/Viagra.csv"
mkdir -p /home/ga/Documents/JASP

if [ ! -f "$DATASET_SOURCE" ]; then
    echo "Error: Source dataset not found at $DATASET_SOURCE"
    exit 1
fi

# Copy dataset (ensuring no stale state from previous runs)
cp "$DATASET_SOURCE" "$DATASET_DEST"
chown ga:ga "$DATASET_DEST"
chmod 644 "$DATASET_DEST"

echo "Dataset prepared at $DATASET_DEST"

# Launch JASP with the dataset
# We use setsid and nohup to ensure it persists, and verify the launcher exists
if [ ! -x "/usr/local/bin/launch-jasp" ]; then
    echo "Error: JASP launcher not found"
    exit 1
fi

echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET_DEST' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window to appear
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Short sleep to allow UI to render
sleep 5

# Maximize the JASP window
echo "Maximizing JASP window..."
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Capture initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="