#!/bin/bash
set -e
echo "=== Setting up FRET Sensitized Emission Analysis Task ==="

# Define directories
DATA_DIR="/home/ga/Fiji_Data/raw/fret_experiment"
RESULTS_DIR="/home/ga/Fiji_Data/results/fret"

# Create directories as user ga
su - ga -c "mkdir -p $DATA_DIR"
su - ga -c "mkdir -p $RESULTS_DIR"

# Clean previous results
rm -f "$RESULTS_DIR/corrected_fret.tif" 2>/dev/null || true
rm -f /tmp/fret_task_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_time

# Generate Synthetic Data using Python
# We use the installed python3 environment which includes numpy and scikit-image/PIL
echo "Generating synthetic FRET data..."

cat << 'PYEOF' > /tmp/generate_fret_data.py
import numpy as np
from PIL import Image
import os
import random

# Settings
width, height = 512, 512
beta = 0.28  # Donor bleed-through
gamma = 0.19 # Acceptor cross-excitation
noise_level = 2.0

# Initialize empty arrays (float for calculation)
donor = np.zeros((height, width), dtype=np.float32) + 10.0  # background
acceptor = np.zeros((height, width), dtype=np.float32) + 10.0
true_fret = np.zeros((height, width), dtype=np.float32)

# Helper to draw a fuzzy blob
def draw_blob(arr, cx, cy, radius, intensity):
    y, x = np.ogrid[:height, :width]
    mask = (x - cx)**2 + (y - cy)**2 <= radius**2
    # Simple flat blob with slight gaussian-like falloff for realism could be better, 
    # but flat is sufficient for quantitative verification of arithmetic.
    # Let's do a simple soft edge.
    dist = np.sqrt((x - cx)**2 + (y - cy)**2)
    blob = np.clip((radius - dist) / (radius * 0.2), 0, 1) * intensity
    arr += blob

# Region 1: Top-Left (Donor Only control)
# High Donor, Low Acceptor, Zero FRET
# Center roughly (125, 125)
draw_blob(donor, 125, 125, 60, 200.0)
draw_blob(acceptor, 125, 125, 60, 20.0)

# Region 2: Top-Right (Acceptor Only control)
# Low Donor, High Acceptor, Zero FRET
# Center roughly (387, 125)
draw_blob(donor, 387, 125, 60, 20.0)
draw_blob(acceptor, 387, 125, 60, 200.0)

# Region 3: Bottom-Center (True FRET interaction)
# Med Donor, Med Acceptor, High FRET
# Center roughly (256, 387)
draw_blob(donor, 256, 387, 60, 150.0)
draw_blob(acceptor, 256, 387, 60, 150.0)
draw_blob(true_fret, 256, 387, 60, 100.0)

# Construct Raw FRET channel
# Raw = True_FRET + (beta * Donor) + (gamma * Acceptor)
raw_fret = true_fret + (beta * donor) + (gamma * acceptor)

# Add noise
def add_noise(arr):
    return arr + np.random.normal(0, noise_level, arr.shape)

donor_final = np.clip(add_noise(donor), 0, 65535).astype(np.uint16)
acceptor_final = np.clip(add_noise(acceptor), 0, 65535).astype(np.uint16)
raw_fret_final = np.clip(add_noise(raw_fret), 0, 65535).astype(np.uint16)

# Save images
output_dir = "/home/ga/Fiji_Data/raw/fret_experiment"
Image.fromarray(donor_final).save(os.path.join(output_dir, "donor_channel.tif"))
Image.fromarray(acceptor_final).save(os.path.join(output_dir, "acceptor_channel.tif"))
Image.fromarray(raw_fret_final).save(os.path.join(output_dir, "fret_raw_channel.tif"))

print(f"Generated 3 images in {output_dir}")
PYEOF

# Run generation script as ga user
chown ga:ga /tmp/generate_fret_data.py
su - ga -c "python3 /tmp/generate_fret_data.py"

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
sleep 10

# Wait for Fiji window
echo "Waiting for Fiji..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize Fiji
DISPLAY=:1 wmctrl -r "fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="