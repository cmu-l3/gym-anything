#!/bin/bash
set -e
echo "=== Setting up ROI Measurement Export task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Prepare directories
DATA_DIR="/home/ga/Fiji_Data/raw"
OUTPUT_DIR="/home/ga/Fiji_Data/results/roi_analysis"
mkdir -p "$DATA_DIR"
mkdir -p "$OUTPUT_DIR"

# Clean previous results to ensure fresh start
rm -rf "$OUTPUT_DIR"/*
chown -R ga:ga "$OUTPUT_DIR"

# 3. Prepare the specific image (simulated fluorescence)
# We need a specific image to ensure the task is standardized.
# We'll use one of the BBBC005 images if available, or create a synthetic one if not.
TARGET_IMAGE="$DATA_DIR/analysis_image.tif"

# Check if BBBC005 is already downloaded (from env setup)
BBBC_SRC="/opt/fiji_samples/BBBC005"
FOUND_IMG=""

if [ -d "$BBBC_SRC" ]; then
    # Look for a w2 (nuclear/fluorescence) image with moderate density (e.g. C17 or similar)
    # The pattern is usually *w2*.TIF
    FOUND_IMG=$(find "$BBBC_SRC" -name "*w2*.TIF" | head -n 1)
fi

if [ -n "$FOUND_IMG" ] && [ -f "$FOUND_IMG" ]; then
    echo "Using real BBBC005 image: $FOUND_IMG"
    cp "$FOUND_IMG" "$TARGET_IMAGE"
else
    echo "BBBC005 not found, generating fallback sample..."
    # Generate a simple noisy image with blobs using Python
    python3 -c "
import numpy as np
from PIL import Image, ImageDraw
import random

# Create a 696x520 image (standard BBBC005 size)
w, h = 696, 520
arr = np.random.normal(20, 5, (h, w)).astype(np.uint8)
img = Image.fromarray(arr)
draw = ImageDraw.Draw(img)

# Draw some 'cells'
for i in range(20):
    x = random.randint(50, w-50)
    y = random.randint(50, h-50)
    r = random.randint(10, 30)
    intensity = random.randint(100, 255)
    draw.ellipse([x-r, y-r, x+r, y+r], fill=intensity, outline=None)

img.save('$TARGET_IMAGE')
"
fi

# Ensure permissions
chown ga:ga "$TARGET_IMAGE"

# 4. Create info file about scale
cat > "$DATA_DIR/scale_info.txt" << 'EOF'
Image Calibration Info
======================
Pixel Width: 0.65 microns
Pixel Height: 0.65 microns
Unit: micron
EOF
chown ga:ga "$DATA_DIR/scale_info.txt"

# 5. Launch Fiji with the image loaded
echo "Launching Fiji..."
pkill -f "fiji" || true
pkill -f "ImageJ" || true
sleep 1

# Launch as ga user
su - ga -c "DISPLAY=:1 /usr/local/bin/fiji '$TARGET_IMAGE' &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|Fiji"; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize main window
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure the image window is also visible/focused if separate
DISPLAY=:1 wmctrl -a "analysis_image.tif" 2>/dev/null || true

# 6. Open ROI Manager (helper for the agent)
# This is optional but helpful. The agent can also open it.
# We'll leave it to the agent as part of the task is "use ROI Manager".

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="