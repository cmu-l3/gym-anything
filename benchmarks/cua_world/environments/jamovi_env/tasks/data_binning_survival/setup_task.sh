#!/bin/bash
set -e
echo "=== Setting up data_binning_survival task ==="

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    # Fallback to copy if not already in Documents (setup_jamovi.sh usually does this)
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET" || \
    wget -q -O "$DATASET" "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/carData/TitanicSurvival.csv"
    chown ga:ga "$DATASET"
fi

# 3. Clean up previous run artifacts
rm -f "/home/ga/Documents/Jamovi/Titanic_Age_Analysis.omv"
rm -f "/home/ga/Documents/Jamovi/survival_odds.txt"

# 4. Kill any running Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# 5. Launch Jamovi with the dataset
# Using setsid to detach from the shell so it survives
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "TitanicSurvival"; then
        echo "Jamovi window found."
        break
    fi
    sleep 1
done

# 7. Maximize and focus
# Note: Jamovi window title usually reflects the open filename
sleep 2
DISPLAY=:1 wmctrl -r "TitanicSurvival" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "TitanicSurvival" 2>/dev/null || true

# 8. Dismiss any potential "Welcome" or "Update" dialogs if they appear
# Sending Escape key blindly just in case
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="