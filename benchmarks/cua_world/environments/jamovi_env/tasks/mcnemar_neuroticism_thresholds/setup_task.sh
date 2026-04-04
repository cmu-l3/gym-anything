#!/bin/bash
set -e
echo "=== Setting up McNemar Neuroticism Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jamovi is not running
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Ensure dataset exists
DATASET_SOURCE="/opt/jamovi_datasets/extract_bfi_neuroticism.py"
DATASET_DEST="/home/ga/Documents/Jamovi/NeuroticiIndex.csv"

mkdir -p /home/ga/Documents/Jamovi

if [ ! -f "$DATASET_DEST" ]; then
    echo "Generating Neuroticism dataset..."
    if [ -f "$DATASET_SOURCE" ]; then
        python3 "$DATASET_SOURCE"
        # Ensure it was created
        if [ ! -f "$DATASET_DEST" ]; then
            echo "ERROR: Failed to generate dataset."
            exit 1
        fi
    else
        echo "ERROR: Generator script not found."
        exit 1
    fi
fi

# Ensure correct permissions
chown -R ga:ga /home/ga/Documents/Jamovi
chmod 644 "$DATASET_DEST"

echo "Dataset ready at $DATASET_DEST"

# Start Jamovi with the dataset loaded
echo "Launching Jamovi..."
# Uses setsid so the process survives when su exits.
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET_DEST' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "NeuroticiIndex"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus the window
DISPLAY=:1 wmctrl -a "NeuroticiIndex" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="