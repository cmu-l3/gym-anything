#!/bin/bash
set -e
echo "=== Setting up phase_confluence_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define directories
DATA_DIR="/home/ga/Fiji_Data/raw/confluence"
RESULTS_DIR="/home/ga/Fiji_Data/results/confluence"
GT_DIR="/var/lib/fiji/ground_truth"

# Create directories
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
mkdir -p "$GT_DIR"
chmod 777 "$RESULTS_DIR"

# Clean previous results
rm -f "$RESULTS_DIR/confluence_mask.png"
rm -f "$RESULTS_DIR/confluence_report.txt"

# Download HeLa Cells sample (standard ImageJ sample)
# We try multiple sources
IMAGE_URL="https://imagej.nih.gov/ij/images/hela-cells.zip"
TARGET_FILE="$DATA_DIR/hela-cells.tif"

echo "Downloading sample data..."
if [ ! -f "$TARGET_FILE" ]; then
    cd /tmp
    wget -q --timeout=30 "$IMAGE_URL" -O hela.zip || \
    wget -q --timeout=30 "https://wsr.imagej.net/images/hela-cells.zip" -O hela.zip
    
    if [ -f hela.zip ]; then
        unzip -q -o hela.zip
        # It might unzip as 'hela-cells.tif' or inside a folder
        find . -name "hela-cells.tif" -exec mv {} "$TARGET_FILE" \;
        rm -f hela.zip
    else
        # Fallback to creating a synthetic image if download fails (unlikely)
        echo "WARNING: Download failed. Using blobs sample as fallback."
        cp /opt/fiji/samples/blobs.gif "$TARGET_FILE" 2>/dev/null || true
    fi
fi

# Set permissions
chown -R ga:ga "/home/ga/Fiji_Data"

# Generate Ground Truth using Python (scikit-image)
# We do this hidden from the agent to have a baseline for verification
echo "Generating ground truth..."
python3 -c "
import numpy as np
from skimage import io, filters, morphology, exposure
from skimage.util import img_as_ubyte

try:
    # Load image
    img = io.imread('$TARGET_FILE')
    
    # Pre-processing similar to standard phase contrast workflow
    # 1. Entropy or Variance filter to detect texture
    from skimage.filters.rank import entropy
    from skimage.morphology import disk
    
    # Normalize to 8-bit
    img_8bit = exposure.rescale_intensity(img, out_range=(0, 255)).astype(np.uint8)
    
    # Entropy filter (radius 2)
    entr_img = entropy(img_8bit, disk(2))
    
    # Thresholding (Otsu)
    thresh = filters.threshold_otsu(entr_img)
    binary = entr_img > thresh
    
    # Fill holes and cleanup
    binary = morphology.remove_small_objects(binary, min_size=50)
    binary = morphology.remove_small_holes(binary, area_threshold=500)
    
    # Calculate confluence
    confluence = np.sum(binary) / binary.size * 100
    
    # Save GT
    io.imsave('$GT_DIR/hela_gt.png', img_as_ubyte(binary), check_contrast=False)
    with open('$GT_DIR/expected_confluence.txt', 'w') as f:
        f.write(f'{confluence:.2f}')
        
    print(f'Ground truth generated: {confluence:.2f}%')

except Exception as e:
    print(f'GT Generation failed: {e}')
    # Create dummy GT if fails
    io.imsave('$GT_DIR/hela_gt.png', np.zeros((100,100), dtype=np.uint8))
    with open('$GT_DIR/expected_confluence.txt', 'w') as f:
        f.write('0')
"

# Launch Fiji
echo "Launching Fiji..."
if ! pgrep -f "ImageJ" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/fiji &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ImageJ"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="