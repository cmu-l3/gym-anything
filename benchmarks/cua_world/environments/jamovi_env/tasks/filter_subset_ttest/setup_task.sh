#!/bin/bash
set -e
echo "=== Setting up filter_subset_ttest task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Verify dataset exists
DATASET="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "ERROR: ToothGrowth.csv not found at expected location"
    # Fallback copy if missing
    if [ -f "/opt/jamovi_datasets/ToothGrowth.csv" ]; then
        cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATASET"
        chown ga:ga "$DATASET"
    else
        exit 1
    fi
fi

# Remove any previous task artifacts to ensure clean state
rm -f /home/ga/Documents/Jamovi/ToothGrowth_Filtered.omv
rm -f /home/ga/Documents/Jamovi/filtered_ttest_results.txt

# Kill any existing Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Launch Jamovi with ToothGrowth dataset
# Using setsid to detach from shell, su to run as user 'ga'
echo "Launching Jamovi with ToothGrowth.csv..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "jamovi"; then
        echo "Jamovi window detected after ${i}s"
        break
    fi
    sleep 2
done

# Additional wait for full UI initialization (Electron app)
sleep 15

# Maximize and focus window
# Note: Jamovi window title often matches the filename ("ToothGrowth")
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "ToothGrowth" 2>/dev/null || DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== filter_subset_ttest task setup complete ==="