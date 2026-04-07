#!/bin/bash
echo "=== Setting up Raster to Vector Conversion task ==="

# 1. Clean up potential artifacts from previous runs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure input data exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading missing Landsat data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# 4. Start SNAP if not running
if ! pgrep -f "org.esa.snap" > /dev/null; then
    echo "Starting SNAP Desktop..."
    su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"
fi

# 5. Wait for the SNAP window to be ready
echo "Waiting for SNAP window to appear..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

# Give the Java UI an extra moment to render
sleep 8

# 6. Maximize and focus SNAP
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Dismiss any potential lingering dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 7. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="