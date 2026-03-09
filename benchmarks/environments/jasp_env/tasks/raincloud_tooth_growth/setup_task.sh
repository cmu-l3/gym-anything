#!/bin/bash
set -e
echo "=== Setting up JASP Raincloud Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists in the user's documents
DATASET_SOURCE="/opt/jasp_datasets/Tooth Growth.csv"
DATASET_DEST="/home/ga/Documents/JASP/ToothGrowth.csv"

mkdir -p "$(dirname "$DATASET_DEST")"

if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    chmod 644 "$DATASET_DEST"
    echo "Dataset prepared at $DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    # Try backup location or fail
    if [ -f "/opt/jasp_datasets/ToothGrowth.csv" ]; then
         cp "/opt/jasp_datasets/ToothGrowth.csv" "$DATASET_DEST"
         chown ga:ga "$DATASET_DEST"
    else
         echo "Critical error: Dataset missing."
         exit 1
    fi
fi

# Clean up any previous results
rm -f "/home/ga/Documents/JASP/ToothGrowth_Raincloud.jasp" 2>/dev/null || true

# Kill any existing JASP instances to ensure fresh start
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Launch JASP (empty, without pre-loading the file, per task description)
# The agent must learn to open the file.
echo "Starting JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP to load..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize JASP window
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss "Welcome" or "Update" dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="