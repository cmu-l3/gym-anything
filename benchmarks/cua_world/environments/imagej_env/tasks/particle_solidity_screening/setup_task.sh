#!/bin/bash
# Setup script for Particle Solidity Screening task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Particle Solidity Screening Task ==="

# Define directories
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Create directories with proper permissions
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results to prevent gaming
rm -f "$RESULTS_DIR/solidity_measurements.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/roughest_particle.txt" 2>/dev/null || true
rm -f /tmp/solidity_task_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Ensure clean Fiji state
echo "Killing existing Fiji instances..."
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

# Setup display environment
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Function to launch and verify Fiji
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    
    # Launch Fiji
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &
    
    # Wait for window
    echo "Waiting for Fiji window..."
    local started=false
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji window detected after ${i}s"
            started=true
            break
        fi
        sleep 1
    done
    
    if [ "$started" = false ]; then
        return 1
    fi
    
    sleep 5
    
    # Dismiss updates if needed
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    fi
    
    return 0
}

# Launch loop
FIJI_RUNNING=false
for attempt in 1 2 3; do
    if launch_and_verify_fiji $attempt; then
        FIJI_RUNNING=true
        break
    else
        kill_fiji
        sleep 5
    fi
done

if [ "$FIJI_RUNNING" = false ]; then
    echo "CRITICAL: Failed to launch Fiji"
    exit 1
fi

# Maximize Fiji
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="