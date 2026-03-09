#!/bin/bash
set -e
echo "=== Setting up Colony Counting Classification task ==="

# 1. Define paths
DATA_DIR="/home/ga/Fiji_Data/raw/colonies"
RESULTS_DIR="/home/ga/Fiji_Data/results/colonies"

# 2. Create directories with correct permissions
su - ga -c "mkdir -p '$DATA_DIR'"
su - ga -c "mkdir -p '$RESULTS_DIR'"

# 3. Clean previous results
rm -f "$RESULTS_DIR"/* 2>/dev/null || true

# 4. Prepare Data
# Download the standard ImageJ Cell_Colony sample if not present
if [ ! -f "$DATA_DIR/cell_colony.tif" ]; then
    echo "Downloading Cell_Colony image..."
    
    # Try downloading the original JPG
    wget -q --timeout=30 "https://imagej.net/images/Cell_Colony.jpg" -O "/tmp/Cell_Colony.jpg" 2>/dev/null || \
    wget -q --timeout=30 "https://imagej.nih.gov/ij/images/Cell_Colony.jpg" -O "/tmp/Cell_Colony.jpg" 2>/dev/null || true
    
    if [ -f "/tmp/Cell_Colony.jpg" ]; then
        # Convert to TIFF using Python/PIL to ensure compatibility and consistent starting state
        python3 -c "
from PIL import Image
try:
    img = Image.open('/tmp/Cell_Colony.jpg')
    img.save('$DATA_DIR/cell_colony.tif', format='TIFF')
    print('Converted Cell_Colony.jpg to TIFF')
except Exception as e:
    print(f'Error converting image: {e}')
"
        rm -f "/tmp/Cell_Colony.jpg"
    else
        echo "WARNING: Failed to download Cell_Colony.jpg. Creating a placeholder (task will be harder)."
        # Create a synthetic placeholder if download fails (fallback)
        convert -size 512x512 xc:white -fill black -draw "circle 100,100 110,110 circle 200,200 220,220" "$DATA_DIR/cell_colony.tif"
    fi
fi

# Ensure ownership
chown -R ga:ga "$DATA_DIR" "$RESULTS_DIR"

# 5. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 6. Launch Fiji
echo "Launching Fiji..."
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    # Fallback launch
    su - ga -c "DISPLAY=:1 fiji" &
fi

# 7. Wait for Fiji window
echo "Waiting for Fiji to load..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ" >/dev/null; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# 8. Maximize window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="