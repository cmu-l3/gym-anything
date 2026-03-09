#!/bin/bash
set -e
echo "=== Setting up factorial_anova task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/Documents/Jamovi/ToothGrowth_ANOVA.omv
rm -f /home/ga/Documents/Jamovi/anova_report.txt
rm -f /tmp/task_result.json

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying ToothGrowth.csv..."
    mkdir -p /home/ga/Documents/Jamovi
    # Source is prepared in environment setup, but fallback just in case
    if [ -f "/opt/jamovi_datasets/ToothGrowth.csv" ]; then
        cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATASET"
    else
        # Fallback download if env setup failed somehow
        wget -q -O "$DATASET" "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/datasets/ToothGrowth.csv"
    fi
    chown ga:ga "$DATASET"
fi

# Kill any existing Jamovi instances to ensure fresh state
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (empty state, user must open file)
# Using setsid to detach from shell, su - ga to run as user
echo "Starting Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the window
sleep 3
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="