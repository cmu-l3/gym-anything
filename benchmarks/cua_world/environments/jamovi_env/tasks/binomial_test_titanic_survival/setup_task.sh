#!/bin/bash
set -e
echo "=== Setting up Binomial Test Titanic Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Prepare Data
# ============================================================
DATA_DIR="/home/ga/Documents/Jamovi"
DATA_FILE="$DATA_DIR/TitanicSurvival.csv"
OUTPUT_FILE="$DATA_DIR/TitanicBinomialTest.omv"

mkdir -p "$DATA_DIR"

# Ensure the source data exists
if [ ! -f "$DATA_FILE" ]; then
    echo "Copying TitanicSurvival.csv from system datasets..."
    if [ -f "/opt/jamovi_datasets/TitanicSurvival.csv" ]; then
        cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATA_FILE"
    else
        echo "ERROR: Source dataset not found!"
        exit 1
    fi
fi

# Set permissions
chown -R ga:ga "$DATA_DIR"
chmod 644 "$DATA_FILE"

# Clean up any previous run's output to prevent false positives
rm -f "$OUTPUT_FILE"

# ============================================================
# 2. Launch Jamovi (Empty State)
# ============================================================
echo "Launching Jamovi..."
# Kill any existing instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch empty Jamovi
# Use setsid to detach from shell, ensure env vars are set
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Wait for UI to fully load
sleep 10

# Maximize the window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any "Welcome" or "What's New" dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# ============================================================
# 3. Capture Initial State
# ============================================================
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="