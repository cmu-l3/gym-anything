#!/bin/bash
set -e
echo "=== Setting up Cohort Survival Analysis Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jamovi directory exists
mkdir -p /home/ga/Documents/Jamovi

# Ensure the dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    if [ -f "/opt/jamovi_datasets/TitanicSurvival.csv" ]; then
        cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
        chown ga:ga "$DATASET"
    else
        echo "ERROR: TitanicSurvival.csv not found in /opt/jamovi_datasets"
        exit 1
    fi
fi

# Clean up any previous runs
rm -f /home/ga/Documents/Jamovi/Titanic_Cohorts.omv
rm -f /home/ga/Documents/Jamovi/cohort_report.txt

# Start Jamovi with the dataset loaded
# Using setsid to detach from the shell so it survives
echo "Starting Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "TitanicSurvival"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Wait a bit for UI to fully load
sleep 5

# Maximize the window (finding it by the file name in title)
DISPLAY=:1 wmctrl -r "TitanicSurvival" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "TitanicSurvival" 2>/dev/null || true

# Dismiss any potential first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="