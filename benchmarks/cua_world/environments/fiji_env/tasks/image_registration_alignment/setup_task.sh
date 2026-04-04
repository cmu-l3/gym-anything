#!/bin/bash
set -e
echo "=== Setting up image registration task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Fiji_Data/raw/registration
mkdir -p /home/ga/Fiji_Data/results/registration
mkdir -p /var/lib/registration_ground_truth

# Clean previous results
rm -f /home/ga/Fiji_Data/results/registration/* 2>/dev/null || true

# Find a source image (BBBC005 or fallback)
BBBC_DIR="/opt/fiji_samples/BBBC005"
SRC_IMAGE=""

# Look for a TIF file in BBBC005
if [ -d "$BBBC_DIR" ]; then
    SRC_IMAGE=$(find "$BBBC_DIR" -type f -name "*.TIF" -size +20k 2>/dev/null | head -1)
fi

# Fallback to built-in blobs if needed
if [ -z "$SRC_IMAGE" ]; then
    echo "Downloading fallback sample..."
    wget -q "https://imagej.net/images/blobs.gif" -O /tmp/blobs.gif
    SRC_IMAGE="/tmp/blobs.gif"
fi

echo "Using source image: $SRC_IMAGE"

# Python script to generate reference and shifted images
python3 << PYEOF
import numpy as np
from PIL import Image
import json
import os
import math
from PIL import ImageTransform

src_path = "$SRC_IMAGE"
out_dir = "/home/ga/Fiji_Data/raw/registration"
gt_dir = "/var/lib/registration_ground_truth"

# Load and convert to grayscale
try:
    img = Image.open(src_path).convert("L")
    
    # Resize if too large or small (target ~512x512 for speed)
    w, h = img.size
    if max(w, h) > 1024 or min(w, h) < 100:
        img = img.resize((512, 512), Image.LANCZOS)
    
    # Save Reference
    ref_path = os.path.join(out_dir, "reference_micrograph.tif")
    img.save(ref_path)
    
    # Define Transformation
    # We want the agent to find these values
    dx = 23.0    # pixels right
    dy = 17.0    # pixels down
    angle = 2.5  # degrees counter-clockwise
    
    # Apply transformation to create "Shifted" image
    # Note: We transform the image such that it appears shifted/rotated.
    # To simulate the sample moving +dx, +dy, the image content moves +dx, +dy.
    
    angle_rad = math.radians(angle)
    cx, cy = img.size[0] / 2, img.size[1] / 2
    
    # Inverse transform logic for PIL
    # We want: x_new = x_old * cos - y_old * sin + dx
    # PIL affine expects inverse mapping coefficients
    
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)
    
    # Coefficients for: x_src = a*x_dst + b*y_dst + c
    # This effectively pulls the source pixels to the destination
    # To shift content RIGHT by dx, we look LEFT by dx (minus sign)
    
    # Inverse rotation
    a = math.cos(-angle_rad)
    b = -math.sin(-angle_rad)
    d = math.sin(-angle_rad)
    e = math.cos(-angle_rad)
    
    # Inverse translation (corrected for rotation center)
    # This is complex, so we use a simpler mental model:
    # 1. Rotate around center
    # 2. Translate
    
    # Actually, let's just use PIL's rotate and translate sequentially for clarity
    # Rotate (bicubic, expand=False to keep size)
    # Positive angle in PIL rotate() is counter-clockwise
    rotated = img.rotate(angle, resample=Image.BICUBIC, center=(cx, cy), translate=(dx, dy))
    
    # Save Shifted
    shifted_path = os.path.join(out_dir, "shifted_micrograph.tif")
    rotated.save(shifted_path)
    
    # Calculate initial NCC (baseline)
    arr_ref = np.array(img).astype(float)
    arr_shift = np.array(rotated).astype(float)
    
    # Crop borders to avoid edge artifacts in NCC
    m = 20
    c_ref = arr_ref[m:-m, m:-m]
    c_shift = arr_shift[m:-m, m:-m]
    
    ncc = 0.0
    if c_ref.std() > 0 and c_shift.std() > 0:
        ncc = np.corrcoef(c_ref.flatten(), c_shift.flatten())[0, 1]
    
    # Save Ground Truth
    gt = {
        "translation_x": dx,
        "translation_y": dy,
        "rotation_deg": angle,
        "ncc_before": float(ncc),
        "ref_path": ref_path,
        "shifted_path": shifted_path
    }
    
    with open(os.path.join(gt_dir, "ground_truth.json"), "w") as f:
        json.dump(gt, f, indent=2)
        
    print(f"Generated data. Baseline NCC: {ncc:.4f}")

except Exception as e:
    print(f"Error generating data: {e}")
    exit(1)
PYEOF

# Create Task Info file
cat > /home/ga/Fiji_Data/raw/registration/task_info.txt << EOF
Image Registration Task
=======================
Reference Image: reference_micrograph.tif
Shifted Image:   shifted_micrograph.tif

Problem: The shifted image is misaligned (translated and rotated) relative to the reference.
Goal: Register the shifted image to match the reference.

Instructions:
1. Open both images.
2. Align them using plugins like StackReg, TurboReg, or SIFT.
3. Save the aligned image as 'registered_micrograph.tif'.
4. Save a difference image as 'difference_image.tif'.
5. Report the approximate translation (X, Y) and rotation in 'alignment_report.txt'.
EOF

# Set ownership
chown -R ga:ga /home/ga/Fiji_Data/raw/registration
chown -R ga:ga /home/ga/Fiji_Data/results/registration
chmod 755 /var/lib/registration_ground_truth
chmod 644 /var/lib/registration_ground_truth/ground_truth.json

# Launch Fiji
echo "Launching Fiji..."
if ! pgrep -f "fiji" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh &"
    sleep 10
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="