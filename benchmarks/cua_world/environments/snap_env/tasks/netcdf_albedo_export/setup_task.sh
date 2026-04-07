#!/bin/bash
echo "=== Setting up NetCDF Albedo Export task ==="

# Install python NetCDF utility to evaluate the output without needing internet later
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq netcdf-bin python3-netcdf4 2>/dev/null || true

# Clean up any potential stale outputs
EXPORT_DIR="/home/ga/snap_exports"
rm -rf "$EXPORT_DIR" 2>/dev/null || true
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"

# Ensure source data is available
DATA_DIR="/home/ga/snap_data"
DATA_FILE="$DATA_DIR/landsat_multispectral.tif"

if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading source Landsat data..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga "$DATA_DIR"
fi
echo "Source data ready: $(ls -lh "$DATA_FILE")"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing SNAP instances
pkill -f "snap" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop as the agent user
echo "Starting SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash &"

# Wait for the SNAP window to become available
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

# Allow time for internal initialization and dialogs
sleep 15

# Dismiss possible startup dialogs (like plugin updates)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus SNAP window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Take an initial screenshot for VLM framework trajectories
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="