#!/bin/bash
set -e
echo "=== Setting up Bayesian Linear Regression Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Prepare Data
# ============================================================
DATA_DIR="/home/ga/Documents/JASP"
SOURCE_DATA="/opt/jasp_datasets/Exam Anxiety.csv"
TARGET_DATA="$DATA_DIR/ExamAnxiety.csv"

mkdir -p "$DATA_DIR"

if [ -f "$SOURCE_DATA" ]; then
    echo "Copying dataset..."
    cp "$SOURCE_DATA" "$TARGET_DATA"
    chown ga:ga "$TARGET_DATA"
    chmod 644 "$TARGET_DATA"
else
    echo "ERROR: Source data not found at $SOURCE_DATA"
    exit 1
fi

# Clean up previous results if they exist
rm -f "$DATA_DIR/ExamAnxiety_BayesRegression.jasp"
rm -f "$DATA_DIR/bayesian_regression_report.txt"

# ============================================================
# 2. Launch JASP (Empty State)
# ============================================================
echo "Killing existing JASP instances..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

echo "Launching JASP..."
# Uses the system-wide launcher we created in env setup
# setsid ensures it runs in a new session
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP to appear..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Focus and Maximize
echo "Configuring window..."
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss welcome screen/dialogs if they appear
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="