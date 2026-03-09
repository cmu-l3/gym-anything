#!/bin/bash
set -e
echo "=== Setting up Partial Correlation Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists in the user's Documents
DATA_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DEST_FILE="/home/ga/Documents/JASP/ExamAnxiety.csv"
RESULTS_FILE="/home/ga/Documents/JASP/PartialCorrelation_Exam.jasp"

# Create directory if needed
mkdir -p "$(dirname "$DEST_FILE")"

# Reset/Prepare Data
if [ -f "$DATA_SOURCE" ]; then
    cp "$DATA_SOURCE" "$DEST_FILE"
    chmod 644 "$DEST_FILE"
    chown ga:ga "$DEST_FILE"
    echo "Dataset reset: $DEST_FILE"
else
    echo "ERROR: Source dataset not found at $DATA_SOURCE"
    exit 1
fi

# Clean up previous results
rm -f "$RESULTS_FILE"

# Start JASP (Empty)
# Using setsid to ensure process survival and proper flags
echo "Starting JASP..."
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
fi

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize the window for visibility
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss start dialogs if they appear (updates etc)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="