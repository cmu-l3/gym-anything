#!/bin/bash
set -e
echo "=== Setting up Repeated Measures ANOVA task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the NeuroticiIndex dataset exists
DATASET="/home/ga/Documents/Jamovi/NeuroticiIndex.csv"
if [ ! -f "$DATASET" ]; then
    echo "Extracting NeuroticiIndex.csv from real bfi dataset..."
    mkdir -p /home/ga/Documents/Jamovi
    # Fallback if script is missing, though env should have it
    if [ -f "/opt/jamovi_datasets/extract_bfi_neuroticism.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi_neuroticism.py
    else
        echo "ERROR: Data extraction script missing."
        exit 1
    fi
    chown ga:ga "$DATASET"
fi

# Clean up any previous run artifacts
rm -f /home/ga/Documents/Jamovi/RM_ANOVA_Neuroticism.omv
rm -f /home/ga/Documents/Jamovi/rm_anova_results.txt

# Start Jamovi (empty state, no data loaded)
# We use setsid to detach from the shell so it persists
echo "Starting Jamovi..."
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"
fi

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window found."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Also try matching by class if title fails (initial title might be "jamovi")
DISPLAY=:1 wmctrl -x -r "jamovi.Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any potential welcome dialogs or "What's New" popups
# Press Escape twice just in case
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="