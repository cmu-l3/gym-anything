#!/bin/bash
set -e
echo "=== Setting up Multinomial GOF Test ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Cleanup: Remove any previous output file
OUTPUT_FILE="/home/ga/Documents/JASP/MultinomialGOF.jasp"
rm -f "$OUTPUT_FILE" 2>/dev/null || true

# 3. Data Preparation: Ensure Viagra.csv exists
DATASET_SOURCE="/opt/jasp_datasets/Viagra.csv"
DATASET_DEST="/home/ga/Documents/JASP/Viagra.csv"
mkdir -p "/home/ga/Documents/JASP"

if [ ! -f "$DATASET_DEST" ]; then
    echo "Restoring dataset from source..."
    cp "$DATASET_SOURCE" "$DATASET_DEST" 2>/dev/null || true
    # Fallback if source missing (should cover by env setup)
    if [ ! -f "$DATASET_DEST" ]; then
        echo "Error: Viagra.csv not found in /opt/jasp_datasets"
        exit 1
    fi
fi
chown ga:ga "$DATASET_DEST"
chmod 644 "$DATASET_DEST"

# 4. State Setup: Ensure JASP is running (Empty State)
# The task description says "JASP is open with no data loaded"
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    # Launch without arguments to start empty
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..40}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Window Management
echo "Maximizing JASP window..."
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Capture Initial State
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="