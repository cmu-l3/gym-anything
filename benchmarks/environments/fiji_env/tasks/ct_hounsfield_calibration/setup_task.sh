#!/bin/bash
set -e
echo "=== Setting up CT Hounsfield Calibration task ==="

# 1. Create Directories
mkdir -p /home/ga/Fiji_Data/raw/ct
mkdir -p /home/ga/Fiji_Data/results/ct
chown -R ga:ga /home/ga/Fiji_Data

# 2. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time

# 3. Prepare Data
# We will download the standard 'Head' CT sample from ImageJ, 
# then use Python to "uncalibrate" it by applying a random linear transform.
# This ensures the agent CANNOT just look up the values; they must measure them.

cat << 'PYEOF' > /tmp/prepare_ct.py
import os
import numpy as np
import random
from PIL import Image
import urllib.request
import json

# Locations
output_raw = "/home/ga/Fiji_Data/raw/ct/patient_ct_raw.tif"
ground_truth_file = "/tmp/ct_ground_truth.json"

# Download standard sample (16-bit tiff)
# The "CT" sample in ImageJ is often 16-bit signed or unsigned.
url = "https://imagej.nih.gov/ij/images/ct.dcm" # DICOM often easier to get raw data from, but let's use a simple TIF if available or convert
# Alternative: Generate a synthetic phantom if download fails, but real data is required.
# Let's try the Head sample zip which contains the tiff
url_zip = "https://imagej.nih.gov/ij/images/ct.zip"

print("Downloading CT sample...")
try:
    # We'll generate a high-quality synthetic phantom if we can't get the file, 
    # but let's try to get a real slice first.
    # Actually, let's use scikit-image's shepp-logan phantom or similar if download fails? 
    # No, strict real data requirement.
    
    # Let's use the 'M51' galaxy example as a fallback? No, not medical.
    # Let's use the standard 'Head' sample.
    urllib.request.urlretrieve("https://imagej.nih.gov/ij/images/ct.tif", "/tmp/ct.tif")
    
    img = Image.open("/tmp/ct.tif")
    arr = np.array(img).astype(float)
    
except Exception as e:
    print(f"Primary download failed: {e}. Generating synthetic phantom for robustness (NOT IDEAL but functional fallback).")
    # Fallback: Simple phantom
    arr = np.zeros((512, 512), dtype=float)
    # Background (Air) = -1000
    arr[:] = -1000
    # Skull (Circle) = 1000
    y, x = np.ogrid[:512, :512]
    mask_skull = ((x - 256)**2 + (y - 256)**2) < 200**2
    arr[mask_skull] = 1000
    # Brain (Circle) = 40
    mask_brain = ((x - 256)**2 + (y - 256)**2) < 180**2
    arr[mask_brain] = 40
    # Ventricles (Water) = 0
    mask_vent = ((x - 256)**2 + (2*(y - 256))**2) < 40**2
    arr[mask_vent] = 0

# Randomize Calibration Parameters
# Raw = (HU + 1000) * slope + intercept
# Typical CT: HU = pixel * slope + intercept. 
# Here we simulate raw detector counts.
slope = random.uniform(0.8, 1.2)
intercept = random.uniform(100, 500) # Bias offset

# Apply transform
# Assume original image is roughly HU-like (Air ~ -1000, Water ~ 0)
# If it's unsigned 16-bit, Air might be 0.
# The ImageJ 'ct.tif' usually has min/max around 0..65535 or -32768..32767.
# Let's assume the downloaded image is roughly calibrated or at least has contrast.
# We normalize it to -1000..3000 range for consistency before uncalibrating.

min_val = np.min(arr)
max_val = np.max(arr)
if max_val != min_val:
    # Normalize to -1000 (Air) to 3000 (Bone)
    arr_norm = (arr - min_val) / (max_val - min_val) * 4000 - 1000
else:
    arr_norm = arr

# Apply the "Uncalibration"
raw_data = (arr_norm * slope) + intercept

# Clip to valid 16-bit range (0-65535)
raw_data = np.clip(raw_data, 0, 65535).astype(np.uint16)

# Save Raw Image
Image.fromarray(raw_data).save(output_raw)

# Calculate Ground Truth Raw Values
# Air (-1000 HU)
raw_air = (-1000 * slope) + intercept
# Water (0 HU)
raw_water = (0 * slope) + intercept

# Save Ground Truth
gt = {
    "slope": slope,
    "intercept": intercept,
    "raw_air_expected": raw_air,
    "raw_water_expected": raw_water,
    "raw_bone_threshold": (400 * slope) + intercept
}

with open(ground_truth_file, 'w') as f:
    json.dump(gt, f)

print(f"Created {output_raw} with slope={slope:.3f}, intercept={intercept:.3f}")
PYEOF

python3 /tmp/prepare_ct.py

# 4. Set Permissions
chown ga:ga /home/ga/Fiji_Data/raw/ct/patient_ct_raw.tif

# 5. Launch Fiji (Standard)
if [ -f /home/ga/launch_fiji.sh ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    su - ga -c "DISPLAY=:1 fiji &" &
fi

# Wait for load
sleep 15
# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="