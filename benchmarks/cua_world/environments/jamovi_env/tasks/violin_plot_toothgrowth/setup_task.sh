#!/bin/bash
set -e
echo "=== Setting up violin_plot_toothgrowth task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Kill any running Jamovi instance to ensure fresh start
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying ToothGrowth.csv from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    # Use the pre-installed dataset if available
    if [ -f "/opt/jamovi_datasets/ToothGrowth.csv" ]; then
        cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATASET"
    else
        # Fallback if setup_jamovi.sh didn't run fully (shouldn't happen in prod)
        echo "len,supp,dose" > "$DATASET"
        echo "4.2,VC,0.5" >> "$DATASET"
        echo "11.5,VC,0.5" >> "$DATASET"
        echo "ERROR: Real dataset missing, created dummy. This may affect verification."
    fi
    chown ga:ga "$DATASET"
fi

# Clean up any previous results
rm -f "/home/ga/Documents/Jamovi/ToothGrowth_Violin.omv"
rm -f "/home/ga/Documents/Jamovi/violin_distribution.png"

echo "Dataset ready: $DATASET"

# Launch Jamovi (Blank state as per description)
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi to appear
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Try generic matching if specific title fails
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="