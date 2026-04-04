#!/bin/bash
set -e
echo "=== Setting up Nuclei Motility Task ==="

# Define paths
DATA_DIR="/home/ga/Fiji_Data/raw/tracking"
RESULTS_DIR="/home/ga/Fiji_Data/results/tracking"
TASK_START_FILE="/tmp/task_start_time"

# Create directories with correct permissions
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "/home/ga/Fiji_Data"

# Clean up any previous results
rm -f "$RESULTS_DIR/track_statistics.csv"
rm -f "$RESULTS_DIR/tracks_visual.png"
rm -f /tmp/tracking_result.json

# Record task start time
date +%s > "$TASK_START_FILE"

# Download the Mitosis sample if not present
TARGET_FILE="$DATA_DIR/mitosis.tif"

if [ ! -f "$TARGET_FILE" ]; then
    echo "Downloading mitosis.tif..."
    # Try multiple mirrors
    wget -q --timeout=30 "https://imagej.nih.gov/ij/images/mitosis.tif" -O "$TARGET_FILE" || \
    wget -q --timeout=30 "https://wsr.imagej.net/images/mitosis.tif" -O "$TARGET_FILE" || \
    {
        echo "WARNING: Failed to download mitosis.tif, falling back to local generation or failure."
        # Fallback: Copy from system samples if available, or create dummy for non-blocking failure
        if [ -f "/opt/fiji_samples/mitosis.tif" ]; then
             cp "/opt/fiji_samples/mitosis.tif" "$TARGET_FILE"
        fi
    }
fi

# Ensure data file ownership
if [ -f "$TARGET_FILE" ]; then
    chown ga:ga "$TARGET_FILE"
fi

# Launch Fiji if not already running
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    echo "Launching Fiji..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
    sleep 10
fi

# Wait for Fiji window and maximize
echo "Waiting for Fiji window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|Fiji"; then
        echo "Fiji window found"
        # Get window ID
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|Fiji" | head -n 1 | awk '{print $1}')
        # Maximize
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Data located at: $TARGET_FILE"