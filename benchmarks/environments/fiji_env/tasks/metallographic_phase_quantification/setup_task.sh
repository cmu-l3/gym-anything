#!/bin/bash
set -e
echo "=== Setting up Metallographic Phase Quantification task ==="

# 1. Directory Setup
# ----------------------------------------------------------------
DATA_DIR="/home/ga/Fiji_Data/raw/metallurgy"
RESULTS_DIR="/home/ga/Fiji_Data/results/metallurgy"

# Create directories with proper ownership
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "/home/ga/Fiji_Data"

# Clean previous results
rm -f "$RESULTS_DIR"/* 2>/dev/null || true

# 2. Acquire Real Data
# ----------------------------------------------------------------
# Source: Wikimedia Commons - Ferrite-pearlite microstructure
# Using a stable, public domain/CC image typical of this analysis
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Ferrite-pearlite_microstructure_in_hot-rolled_carbon_steel.jpg/800px-Ferrite-pearlite_microstructure_in_hot-rolled_carbon_steel.jpg"
IMAGE_PATH="$DATA_DIR/steel_microstructure.jpg"

echo "Downloading microstructure image..."
if ! wget -q --timeout=30 "$IMAGE_URL" -O "$IMAGE_PATH"; then
    echo "Primary download failed. Using fallback..."
    # Fallback: Generate a synthetic microstructure-like texture if download fails
    # This ensures the task doesn't crash on network issues
    convert -size 800x600 plasma:fractal -colorspace Gray -contrast-stretch 10%x90% "$IMAGE_PATH" || \
    cp /opt/fiji_samples/BBBC005/BBBC005_v1_images/SIMCEPImages_A01_C1_F1_s01_w1.TIF "$IMAGE_PATH"
fi

# Ensure image is readable
chmod 644 "$IMAGE_PATH"
chown ga:ga "$IMAGE_PATH"

# 3. Generate Ground Truth
# ----------------------------------------------------------------
# We calculate the expected value using Python (skimage) to mimic the SOP:
# RGB -> Gray -> Median(2) -> Otsu -> Count Dark Pixels
echo "Generating ground truth..."

GT_FILE="/var/lib/app/ground_truth_fraction.txt"
mkdir -p "$(dirname "$GT_FILE")"

python3 << PYEOF
import numpy as np
import sys
import os
try:
    from skimage import io, color, filters, morphology
    from skimage.morphology import disk
    
    # Load image
    img_path = "$IMAGE_PATH"
    if not os.path.exists(img_path):
        print("Image not found")
        sys.exit(1)
        
    img = io.imread(img_path)
    
    # Handle RGB
    if img.ndim == 3:
        gray = color.rgb2gray(img)
        # rgb2gray returns 0-1 float, scale to 0-255 uint8 for consistency with Fiji 8-bit
        gray = (gray * 255).astype(np.uint8)
    else:
        gray = img
        
    # SOP Step 2: Median Filter radius 2
    # Fiji radius=2 approximates a disk of radius 2
    denoised = filters.median(gray, disk(2))
    
    # SOP Step 3: Otsu Thresholding
    thresh = filters.threshold_otsu(denoised)
    
    # SOP Step 4: Measure Dark Phase (Pearlite)
    # Dark pixels are those BELOW the threshold
    binary = denoised < thresh
    
    # Calculate Fraction
    total_pixels = binary.size
    pearlite_pixels = np.sum(binary)
    fraction = (pearlite_pixels / total_pixels) * 100.0
    
    print(f"Calculated GT: {fraction:.2f}%")
    
    with open("$GT_FILE", "w") as f:
        f.write(f"{fraction:.2f}")
        
except Exception as e:
    print(f"GT Generation Error: {e}")
    # Write a fallback safe value if calculation fails (approx for this image)
    with open("$GT_FILE", "w") as f:
        f.write("35.0")
PYEOF

# Ensure GT is hidden from agent
chmod 600 "$GT_FILE"
chown root:root "$GT_FILE"

# 4. Launch Fiji
# ----------------------------------------------------------------
echo "Launching Fiji..."
pkill -f "fiji" || true
pkill -f "ImageJ" || true

# Launch as user ga
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
sleep 10

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ" >/dev/null; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Record Start State
# ----------------------------------------------------------------
date +%s > /tmp/task_start_time
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="