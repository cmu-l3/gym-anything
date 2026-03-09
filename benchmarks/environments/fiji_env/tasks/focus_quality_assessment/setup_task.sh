#!/bin/bash
echo "=== Setting up Focus Quality Assessment Task ==="

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Define paths
DATA_DIR="/home/ga/Fiji_Data/raw/BBBC005"
RESULTS_DIR="/home/ga/Fiji_Data/results/focus_qc"

# Ensure results directory exists and is empty
if [ -d "$RESULTS_DIR" ]; then
    echo "Cleaning previous results..."
    rm -rf "$RESULTS_DIR"
fi
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$RESULTS_DIR"

# Verify input data exists
# The environment install script unpacks BBBC005 into /opt/fiji_samples/BBBC005
# and setup_fiji.sh copies it to ~/Fiji_Data/raw/.
# We verify it's there.
if [ ! -d "$DATA_DIR" ]; then
    echo "Creating data directory..."
    mkdir -p "$DATA_DIR"
    # Fallback copy if missing (should be handled by env, but being safe)
    if [ -d "/opt/fiji_samples/BBBC005" ]; then
        cp -r /opt/fiji_samples/BBBC005/* "$DATA_DIR/" 2>/dev/null || true
    fi
fi

# Ensure permissions
chown -R ga:ga "/home/ga/Fiji_Data"

# Count available w1 images for baseline
W1_COUNT=$(find "$DATA_DIR" -name "*w1*.TIF" 2>/dev/null | wc -l)
echo "$W1_COUNT" > /tmp/initial_w1_count.txt
echo "Found $W1_COUNT w1 images for analysis"

# Launch Fiji if not running
if ! pgrep -f "fiji\|ImageJ" > /dev/null; then
    echo "Launching Fiji..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null; then
            echo "Fiji window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize Fiji window
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="