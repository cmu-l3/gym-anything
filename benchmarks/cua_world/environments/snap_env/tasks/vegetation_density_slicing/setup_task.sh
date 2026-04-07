#!/bin/bash
set -e
echo "=== Setting up vegetation_density_slicing task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean previous task artifacts to ensure a fresh state
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# Ensure the real satellite data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading real Landsat sample dataset..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga /home/ga/snap_data
fi

# Ensure SNAP application is running
if ! pgrep -f "snap" > /dev/null; then
    echo "Starting ESA SNAP..."
    su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash &"
fi

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        break
    fi
    sleep 1
done
sleep 5  # Allow Java UI to fully render

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Dismiss any blocking startup dialogs (like updates)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="