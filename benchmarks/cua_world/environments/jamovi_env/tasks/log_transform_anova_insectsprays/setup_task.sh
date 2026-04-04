#!/bin/bash
set -e
echo "=== Setting up log_transform_anova_insectsprays task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists
DATASET_SOURCE="/opt/jamovi_datasets/InsectSprays.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/InsectSprays.csv"

mkdir -p /home/ga/Documents/Jamovi

if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    echo "Dataset copied to $DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    # Fallback download if missing (should be there from env setup)
    wget -q -O "$DATASET_DEST" "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/datasets/InsectSprays.csv"
    chown ga:ga "$DATASET_DEST"
fi

# Clean up any previous results
rm -f "/home/ga/Documents/Jamovi/InsectSprays_Transformed.omv"
rm -f "/home/ga/Documents/Jamovi/anova_report.txt"

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (empty state)
echo "Starting Jamovi..."
# Uses setsid so the process survives when su exits.
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize window
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss welcome/startup dialogs if any
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="