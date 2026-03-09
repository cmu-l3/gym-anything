#!/bin/bash
set -e
echo "=== Setting up Bain Hypothesis Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure JASP is not running initially
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Ensure the dataset exists in the user's Documents
DATASET_SOURCE="/opt/jasp_datasets/Tooth Growth.csv"
DATASET_DEST="/home/ga/Documents/JASP/ToothGrowth.csv"

mkdir -p "$(dirname "$DATASET_DEST")"

if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    echo "Copied dataset to $DATASET_DEST"
else
    # Fallback download if not in opt
    echo "Downloading dataset..."
    wget -q -O "$DATASET_DEST" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Tooth%20Growth.csv"
fi

# Fix permissions
chown ga:ga "$DATASET_DEST"
chmod 644 "$DATASET_DEST"

# Start JASP (empty)
# We start it empty so the agent has to load the file, verifying they can navigate file open.
# Uses setsid so the process survives when su exits.
echo "Starting JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize JASP
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="