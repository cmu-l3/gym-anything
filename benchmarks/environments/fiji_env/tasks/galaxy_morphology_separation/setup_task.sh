#!/bin/bash
echo "=== Setting up Galaxy Morphology Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create data directories
mkdir -p /home/ga/Fiji_Data/raw/astronomy
mkdir -p /home/ga/Fiji_Data/results/galaxy
chown -R ga:ga /home/ga/Fiji_Data

# Clean previous results
rm -f /home/ga/Fiji_Data/results/galaxy/companion_metrics.csv
rm -f /home/ga/Fiji_Data/results/galaxy/segmentation_map.png
rm -f /tmp/galaxy_result.json

# Download M51 sample image
IMAGE_PATH="/home/ga/Fiji_Data/raw/astronomy/m51.tif"
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Downloading M51 sample..."
    # Try local sample cache first if available (standard in environment)
    if [ -f "/opt/fiji_samples/m51.tif" ]; then
        cp "/opt/fiji_samples/m51.tif" "$IMAGE_PATH"
    else
        wget -q "https://imagej.nih.gov/ij/images/m51.tif" -O "$IMAGE_PATH" || \
        wget -q "https://wsr.imagej.net/images/m51.tif" -O "$IMAGE_PATH"
    fi
    chown ga:ga "$IMAGE_PATH"
fi

# Create a startup macro to open the image automatically
STARTUP_MACRO="/home/ga/Fiji_Data/raw/astronomy/open_m51.ijm"
cat > "$STARTUP_MACRO" << EOF
open("$IMAGE_PATH");
run("Enhance Contrast", "saturated=0.35");
EOF
chown ga:ga "$STARTUP_MACRO"

# Launch Fiji
echo "Launching Fiji..."
if pgrep -f "fiji" > /dev/null; then
    pkill -f "fiji"
    sleep 2
fi

# Launch with macro
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh -macro $STARTUP_MACRO" &

# Wait for window
echo "Waiting for Fiji window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="