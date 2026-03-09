#!/bin/bash
set -e
echo "=== Setting up Hierarchical Regression Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/Jamovi/HierarchicalRegression.omv
rm -f /home/ga/Documents/Jamovi/hierarchical_regression_report.txt
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# 3. Ensure Dataset exists
DATA_FILE="/home/ga/Documents/Jamovi/ExamAnxiety.csv"
if [ ! -f "$DATA_FILE" ]; then
    echo "Restoring ExamAnxiety.csv..."
    cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# 4. Launch Jamovi with dataset
echo "Launching Jamovi..."
# Use setsid to detach from shell, su to run as user ga
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATA_FILE' > /tmp/jamovi.log 2>&1 &"

# 5. Wait for Jamovi window
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5  # Allow UI to render

# 6. Maximize window (Critical for VLM)
DISPLAY=:1 wmctrl -r "ExamAnxiety" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ExamAnxiety" 2>/dev/null || true

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="