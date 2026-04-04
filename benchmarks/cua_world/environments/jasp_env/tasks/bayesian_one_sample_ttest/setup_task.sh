#!/bin/bash
set -e
echo "=== Setting up Bayesian One-Sample T-Test task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean any previous task artifacts
rm -f /home/ga/Documents/JASP/ExamBayesianOneSample.jasp 2>/dev/null || true

# Verify dataset exists and has content
DATASET="/home/ga/Documents/JASP/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "ERROR: ExamAnxiety.csv not found"
    # Fallback copy if missing (should be there from env setup)
    if [ -f "/opt/jasp_datasets/Exam Anxiety.csv" ]; then
        cp "/opt/jasp_datasets/Exam Anxiety.csv" "$DATASET"
        chown ga:ga "$DATASET"
    else
        echo "Critical Error: Dataset missing from system"
        exit 1
    fi
fi

EXAM_SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
echo "Dataset size: ${EXAM_SIZE} bytes"

# Kill any existing JASP instances to ensure clean state
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Launch JASP with the ExamAnxiety dataset
# Uses setsid so the process survives when su exits
echo "Launching JASP with ExamAnxiety.csv..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_task.log 2>&1 &"

# Wait for JASP to fully load (Qt + WebEngine + data loading takes time)
echo "Waiting for JASP to start..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "jasp"; then
        echo "JASP window detected after ${i}s"
        break
    fi
    sleep 1
done
sleep 10  # Additional settle time for data loading

# Dismiss any startup dialogs (like "Check for Updates") if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize JASP window
echo "Maximizing window..."
JASP_WID=$(DISPLAY=:1 wmctrl -l | grep -i "jasp" | head -1 | awk '{print $1}')
if [ -n "$JASP_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$JASP_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$JASP_WID" 2>/dev/null || true
fi

# Take screenshot of initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="