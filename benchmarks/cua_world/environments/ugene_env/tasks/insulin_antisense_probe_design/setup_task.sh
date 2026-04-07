#!/bin/bash
echo "=== Setting up insulin_antisense_probe_design task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories and clean previous state
RESULTS_DIR="/home/ga/UGENE_Data/results/antisense_probe"
rm -rf "$RESULTS_DIR" 2>/dev/null || true
mkdir -p "$RESULTS_DIR"

# Ensure the human insulin gene file is present
DATA_FILE="/home/ga/UGENE_Data/human_insulin_gene.gb"
if [ ! -f "$DATA_FILE" ]; then
    echo "Copying human insulin gene data from /opt/ugene_data..."
    cp /opt/ugene_data/human_insulin_gene.gb "$DATA_FILE" 2>/dev/null || true
fi

# Set proper ownership
chown -R ga:ga /home/ga/UGENE_Data

# Stop any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Start UGENE application in the background
echo "Starting UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${ELAPSED}s"
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    # Give UI time to fully initialize
    sleep 5

    # Dismiss any startup dialogs (Welcome screen, tips, etc.)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize and focus the window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi

    # Take initial state screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot saved to /tmp/task_initial.png"
else
    echo "WARNING: UGENE window did not appear within timeout."
fi

echo "=== Task setup complete ==="