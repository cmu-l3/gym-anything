#!/bin/bash
set -e
echo "=== Setting up robust_ttest_heteroscedasticity task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the Documents directory exists
mkdir -p /home/ga/Documents/Jamovi

# Ensure the dataset exists
DATASET_SOURCE="/opt/jamovi_datasets/InsectSprays.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/InsectSprays.csv"

if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    chmod 644 "$DATASET_DEST"
    echo "Dataset placed at $DATASET_DEST"
else
    echo "ERROR: Source dataset $DATASET_SOURCE not found!"
    exit 1
fi

# Clean up any previous run artifacts
rm -f /home/ga/Documents/Jamovi/Spray_Comparison.omv
rm -f /home/ga/Documents/Jamovi/robust_results.txt

# Ensure Jamovi is running (clean state, no file loaded initially)
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    # Launch with setsid to detach from shell, using the wrapper script
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window to appear (can take 10-20s)
    echo "Waiting for Jamovi window..."
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any startup dialogs (like "Welcome to Jamovi")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="