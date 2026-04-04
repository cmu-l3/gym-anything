#!/bin/bash
set -e
echo "=== Setting up Factorial ANOVA Interaction task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Prepare the dataset
DATA_DIR="/home/ga/Documents/JASP"
DATASET="$DATA_DIR/ToothGrowth.csv"

# Ensure dataset exists (copy from system location if needed)
if [ ! -f "$DATASET" ]; then
    echo "Restoring ToothGrowth.csv..."
    mkdir -p "$DATA_DIR"
    cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET"
    chown ga:ga "$DATASET"
    chmod 644 "$DATASET"
fi

# 3. Clean up previous results
rm -f "$DATA_DIR/ToothGrowth_Factorial.jasp" 2>/dev/null || true

# 4. Start JASP with the dataset
echo "Starting JASP..."
# Kill any existing instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP via the wrapper (setsid ensures it survives su exit)
# We open the CSV directly so the agent starts with data loaded
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and focus
sleep 5 # Wait for UI to paint
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss startup dialogs (e.g., Welcome/Updates)
# Press Escape a few times to close welcome screens
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="