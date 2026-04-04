#!/bin/bash
set -e
echo "=== Setting up Multinomial Logistic Regression task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define paths
DATA_DIR="/home/ga/Documents/Jamovi"
DATASET="$DATA_DIR/TitanicSurvival.csv"
OUTPUT_FILE="$DATA_DIR/MultinomialTitanic.omv"

# Ensure dataset exists
if [ ! -f "$DATASET" ]; then
    echo "Restoring TitanicSurvival.csv..."
    mkdir -p "$DATA_DIR"
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# Verify dataset integrity
ROW_COUNT=$(wc -l < "$DATASET")
if [ "$ROW_COUNT" -lt 1000 ]; then
    echo "ERROR: TitanicSurvival.csv has only $ROW_COUNT rows (expected >1000)"
    # Try to re-download or restore if corrupted
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
fi

# Remove any previous result file to ensure clean state
rm -f "$OUTPUT_FILE"

# Kill any existing Jamovi instance for clean start
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (using setsid to detach from shell)
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Additional wait for full UI initialization
sleep 5

# Maximize and focus the Jamovi window
# Note: Jamovi's window title often changes to the open filename, but starts as "jamovi"
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (e.g., welcome screen) if they appear
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Dataset: $DATASET"
echo "Expected output: $OUTPUT_FILE"