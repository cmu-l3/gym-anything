#!/bin/bash
set -e
echo "=== Setting up Gel Molecular Weight Analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
su - ga -c "mkdir -p /home/ga/Fiji_Data/raw/gel"
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/mw_analysis"
mkdir -p /var/lib/fiji/ground_truth

# Download base image (gel.gif)
echo "Downloading base gel image..."
wget -q -O /tmp/base_gel.gif "https://imagej.nih.gov/ij/images/gel.gif" || \
wget -q -O /tmp/base_gel.gif "https://imagej.net/images/gel.gif"

# Python script to randomize image and calculate ground truth
echo "Generating randomized experimental gel..."
python3 << 'PYEOF'
import numpy as np
from PIL import Image
import json
import os
import random
from scipy.signal import find_peaks

# Load image
img = Image.open("/tmp/base_gel.gif").convert("L")
img_array = np.array(img)

# Define Lane coordinates (approximate X centers for gel.gif)
# Lane 1 (Ladder) is approx around x=30-40
# Lane 3 (Unknown) is approx around x=100-110
lane1_x = 35
lane3_x = 105
lane_width = 20

# Extract lane profiles to find peaks
lane1_profile = np.mean(img_array[:, lane1_x-10:lane1_x+10], axis=1)
lane3_profile = np.mean(img_array[:, lane3_x-10:lane3_x+10], axis=1)

# Find peaks (inverted because bands are dark)
# gel.gif is dark bands on light background, but ImageJ often inverts. 
# Let's check min/max. Usually gel.gif is low values = dark.
# So we look for local minima, or invert and look for maxima.
profile1_inverted = 255 - lane1_profile
profile3_inverted = 255 - lane3_profile

# Find peaks with some prominence
peaks1, _ = find_peaks(profile1_inverted, distance=15, prominence=20)
peaks3, _ = find_peaks(profile3_inverted, distance=15, prominence=20)

# Filter peaks to get the 5 main ones for ladder
# gel.gif usually has 5 clear bands in the first lane
if len(peaks1) > 5:
    # Take the 5 most prominent or just sort by Y if we know expected count
    # Usually they are well spaced. Let's just take the top 5 by intensity
    prominences = _['prominences'] if 'prominences' in _ else []
    # Actually just sorting by Y (index) is safest for ladder order
    peaks1 = sorted(peaks1)[:5] 
elif len(peaks1) < 5:
    # Fallback to hardcoded approx positions if auto-detection fails
    # These are for the standard gel.gif 
    peaks1 = np.array([20, 42, 68, 92, 122])

# Identify main band in Lane 3
if len(peaks3) > 0:
    # Take the strongest peak
    main_peak_3_idx = np.argmax(profile3_inverted[peaks3])
    peak3 = peaks3[main_peak_3_idx]
else:
    peak3 = 58 # approx

# --- RANDOMIZATION ---
# Random scaling factor for height (0.8 to 1.3)
scale_y = random.uniform(0.85, 1.25)
# Random vertical shift/crop (0 to 20 pixels)
offset_y = random.randint(0, 15)

# Resize image
new_width = img.width
new_height = int(img.height * scale_y)
resized_img = img.resize((new_width, new_height), Image.Resampling.BILINEAR)

# Apply offset (crop top)
final_img = resized_img.crop((0, offset_y, new_width, new_height))

# Transform Ground Truth Y coordinates
# Y_new = (Y_old * scale_y) - offset_y
gt_ladder = [(y * scale_y) - offset_y for y in peaks1]
gt_unknown = (peak3 * scale_y) - offset_y

# Calculate Ground Truth MW
# Using Log-Linear fit: ln(MW) = m*y + c
known_mws = [100, 75, 50, 37, 25]
# Use first and last to estimate line (or simple regression)
# Simple regression for robustness
A = np.vstack([gt_ladder, np.ones(len(gt_ladder))]).T
m, c = np.linalg.lstsq(A, np.log(known_mws), rcond=None)[0]
calculated_mw = np.exp(m * gt_unknown + c)

# Save Ground Truth
gt_data = {
    "scale_y": scale_y,
    "offset_y": offset_y,
    "ladder_y": [round(y, 2) for y in gt_ladder],
    "unknown_y": round(gt_unknown, 2),
    "calculated_mw": round(calculated_mw, 2),
    "fit_m": m,
    "fit_c": c
}

with open("/var/lib/fiji/ground_truth/gel_gt.json", "w") as f:
    json.dump(gt_data, f)

# Save Randomized Image
final_img.save("/home/ga/Fiji_Data/raw/gel/experimental_gel.tif")
print(f"Generated gel with scaling {scale_y:.2f} and offset {offset_y}")
PYEOF

# Set permissions
chown ga:ga /home/ga/Fiji_Data/raw/gel/experimental_gel.tif
chmod 644 /var/lib/fiji/ground_truth/gel_gt.json

# Start Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
sleep 10

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Setup complete ==="