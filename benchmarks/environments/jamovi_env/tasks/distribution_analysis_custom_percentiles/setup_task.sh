#!/bin/bash
set -e
echo "=== Setting up Distribution Analysis task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jamovi is not already running (clean state)
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# 3. Prepare the dataset
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from backup..."
    cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATASET" 2>/dev/null || true
    chown ga:ga "$DATASET"
fi

# 4. Launch Jamovi with the dataset loaded
# Using setsid to ensure it runs in a separate session, avoiding SUID issues with flatpak
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety.csv"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done
sleep 5 # Allow UI to render

# 6. Maximize the window
# Note: Jamovi flatpak window title usually matches the filename
DISPLAY=:1 wmctrl -r "ExamAnxiety.csv" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Focus the window
DISPLAY=:1 wmctrl -a "ExamAnxiety.csv" 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="