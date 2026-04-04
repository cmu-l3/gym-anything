#!/bin/bash
echo "=== Setting up ordinal_regression_bigfive task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JASP instance to ensure clean state
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Ensure the dataset exists in the user's documents
# The environment setup usually copies it, but we double check
DATASET_SRC="/opt/jasp_datasets/Big Five Personality Traits.csv"
DATASET_DEST="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

mkdir -p /home/ga/Documents/JASP

if [ ! -f "$DATASET_DEST" ]; then
    echo "Copying dataset..."
    cp "$DATASET_SRC" "$DATASET_DEST" 2>/dev/null || echo "Warning: Source dataset not found at $DATASET_SRC"
    chown ga:ga "$DATASET_DEST"
fi

# Ensure permissions
chown -R ga:ga /home/ga/Documents/JASP
chmod 644 "$DATASET_DEST"

# Start JASP
echo "Starting JASP..."
# Using setsid and nohup pattern compatible with container env
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize JASP window
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="