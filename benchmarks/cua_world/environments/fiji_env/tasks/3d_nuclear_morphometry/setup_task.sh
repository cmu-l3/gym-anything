#!/bin/bash
set -e
echo "=== Setting up 3D Nuclear Morphometry task ==="

# 1. Create Data Directories
echo "Creating directories..."
su - ga -c "mkdir -p /home/ga/Fiji_Data/raw"
su - ga -c "mkdir -p /home/ga/Fiji_Data/results"

# 2. Prepare Data
# The environment install script downloads fluorescence_stack.dv to /opt/fiji_samples/
# We copy it to the user's raw data directory.
if [ -f "/opt/fiji_samples/fluorescence_stack.dv" ]; then
    echo "Copying sample data..."
    cp "/opt/fiji_samples/fluorescence_stack.dv" "/home/ga/Fiji_Data/raw/fluorescence_stack.dv"
    chown ga:ga "/home/ga/Fiji_Data/raw/fluorescence_stack.dv"
else
    # Fallback if file is missing (should not happen in correct env)
    echo "WARNING: Sample data not found in /opt/fiji_samples. Attempting download..."
    wget -q "https://downloads.openmicroscopy.org/images/DV/will/DAPI_NUC.r3d_D3D.dv" \
         -O "/home/ga/Fiji_Data/raw/fluorescence_stack.dv"
    chown ga:ga "/home/ga/Fiji_Data/raw/fluorescence_stack.dv"
fi

# 3. Clean Previous Results
echo "Cleaning previous results..."
rm -f /home/ga/Fiji_Data/results/3d_morphometry.csv 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/3d_object_map.tif 2>/dev/null || true
rm -f /tmp/3d_morphometry_result.json 2>/dev/null || true

# 4. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Fiji
echo "Launching Fiji..."
if pgrep -f "fiji" > /dev/null || pgrep -f "ImageJ" > /dev/null; then
    echo "Fiji is already running."
else
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    sleep 10
fi

# 6. Wait for Window and Maximize
echo "Waiting for Fiji window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ" > /dev/null; then
        echo "Fiji window detected."
        # Maximize
        DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
        DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 7. Initial Screenshot
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="