#!/bin/bash
# Setup script for ml_image_preprocessing task

source /workspace/scripts/task_utils.sh

echo "=== Setting up ML Image Preprocessing Task ==="

# Define directories
DATA_DIR="/home/ga/ImageJ_Data"
PROCESSED_DIR="$DATA_DIR/processed"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and permissions are correct
mkdir -p "$PROCESSED_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results for this specific task
rm -f "$PROCESSED_DIR/blobs_ml_ready.tif" 2>/dev/null || true
rm -f /tmp/ml_preprocessing_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji instance to ensure clean state
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Function to launch and verify Fiji
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    # Launch Fiji without opening any specific image (agent must open sample)
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

    echo "Waiting for Fiji window..."
    local started=false
    for i in $(seq 1 60); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji window detected after ${i}s"
            started=true
            break
        fi
        sleep 1
    done

    [ "$started" = false ] && return 1

    sleep 5

    # Dismiss any Updater dialogs
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
        UPDATER_WID=$(DISPLAY=:1 wmctrl -l | grep -i "Updater" | head -1 | awk '{print $1}')
        [ -n "$UPDATER_WID" ] && DISPLAY=:1 wmctrl -i -a "$UPDATER_WID" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    fi
    
    return 0
}

# Launch Fiji
if launch_and_verify_fiji 1; then
    echo "Fiji started successfully."
else
    echo "Retrying Fiji launch..."
    launch_and_verify_fiji 2
fi

# Maximize Fiji window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="