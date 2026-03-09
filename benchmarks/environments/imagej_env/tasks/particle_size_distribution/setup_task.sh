#!/bin/bash
# Setup script for particle_size_distribution task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Particle Size Distribution Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/size_distribution.csv" 2>/dev/null || true
rm -f /tmp/particle_size_distribution_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji instance
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji (Standard robust launch)
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

    echo "Waiting for Fiji window..."
    local started=false
    for i in $(seq 1 90); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji window detected after ${i}s"
            started=true
            break
        fi
        sleep 1
    done

    [ "$started" = false ] && return 1
    sleep 5
    
    # Dismiss Updater if it appears
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
        UPDATER_WID=$(DISPLAY=:1 wmctrl -l | grep -i "Updater" | head -1 | awk '{print $1}')
        [ -n "$UPDATER_WID" ] && DISPLAY=:1 wmctrl -i -a "$UPDATER_WID" 2>/dev/null || true
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 1
    fi
    
    return 0
}

FIJI_RUNNING=false
for attempt in 1 2 3; do
    if launch_and_verify_fiji $attempt; then
        FIJI_RUNNING=true
        break
    else
        echo "Attempt $attempt failed, retrying..."
        kill_fiji
        sleep 5
    fi
done

if [ "$FIJI_RUNNING" = false ]; then
    echo "CRITICAL ERROR: Failed to start Fiji"
    exit 1
fi

# Maximize Fiji
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="