#!/bin/bash
set -e
echo "=== Setting up Influential Data Identification task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/Jamovi/influential_student_report.txt
rm -f /home/ga/Documents/Jamovi/Influential_Analysis.omv
rm -f /tmp/task_result.json

# 3. Prepare the dataset
# We use the Exam Anxiety dataset.
# The environment installation puts it at /opt/jamovi_datasets/Exam Anxiety.csv
# We copy it to the user's Documents with a safe name (no spaces).
mkdir -p /home/ga/Documents/Jamovi
DATASET_SRC="/opt/jamovi_datasets/Exam Anxiety.csv"
DATASET_DST="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

if [ -f "$DATASET_SRC" ]; then
    cp "$DATASET_SRC" "$DATASET_DST"
    chown ga:ga "$DATASET_DST"
    chmod 644 "$DATASET_DST"
    echo "Dataset prepared at $DATASET_DST"
else
    echo "ERROR: Source dataset not found at $DATASET_SRC"
    exit 1
fi

# 4. Ensure Jamovi is not already running
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# 5. Launch Jamovi with the dataset loaded
echo "Launching Jamovi..."
# Use setsid to detach from the shell so it survives
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET_DST' > /tmp/jamovi_launch.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety"; then
        echo "Jamovi window found."
        break
    fi
    sleep 1
done

# 7. Maximize and focus the window
sleep 5 # Wait for UI to fully render
WID=$(DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# 8. Dismiss any potential "Welcome" or "Update" dialogs
# Press Escape twice just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 9. Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="