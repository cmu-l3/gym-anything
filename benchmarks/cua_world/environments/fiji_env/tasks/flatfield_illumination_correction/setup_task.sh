#!/bin/bash
set -e
echo "=== Setting up Flat-Field Illumination Correction task ==="

# 1. Create directories
mkdir -p /home/ga/Fiji_Data/raw/illumination_test
mkdir -p /home/ga/Fiji_Data/results/flatfield
chown -R ga:ga /home/ga/Fiji_Data

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Generate Vignetted Image (Synthetic Data Generation)
# We create a specific illumination artifact to ensure the task is solvable and measurable.
echo "Generating vignetted test image..."
python3 << 'PYEOF'
import numpy as np
from PIL import Image
import os

# Create a synthetic cell image or use a blob pattern
w, h = 512, 512
# Create background with vignetting
y, x = np.ogrid[:h, :w]
center_y, center_x = h/2, w/2
dist_from_center = np.sqrt((x - center_x)**2 + (y - center_y)**2)
max_dist = np.sqrt(center_x**2 + center_y**2)

# Vignetting function: 1.0 at center, drops to 0.4 at corners
vignette = 1.0 - 0.6 * (dist_from_center / max_dist)**2

# Generate some "cells" (bright spots)
np.random.seed(42)
cells = np.zeros((h, w))
num_cells = 80
for _ in range(num_cells):
    cy = np.random.randint(20, h-20)
    cx = np.random.randint(20, w-20)
    # Gaussian blob for cell
    dist_sq = (x - cx)**2 + (y - cy)**2
    cells += 100 * np.exp(-dist_sq / 100)

# Combine: (Background + Cells) * Vignette + Noise
background = 50 * np.ones((h, w))
img_data = (background + cells) * vignette
noise = np.random.normal(0, 2, (h, w))
img_data += noise

# Clip and convert to uint8
img_data = np.clip(img_data, 0, 255).astype(np.uint8)

# Save
output_path = "/home/ga/Fiji_Data/raw/illumination_test/test_image.tif"
Image.fromarray(img_data).save(output_path)
print(f"Created vignetted image at {output_path}")

# Calculate ground truth uniformity (Corner/Center ratio)
center_roi = img_data[int(h*0.4):int(h*0.6), int(w*0.4):int(w*0.6)]
corner_tl = img_data[0:int(h*0.2), 0:int(w*0.2)]
corner_tr = img_data[0:int(h*0.2), int(w*0.8):]
corner_bl = img_data[int(h*0.8):, 0:int(w*0.2)]
corner_br = img_data[int(h*0.8):, int(w*0.8):]

mean_center = np.mean(center_roi)
mean_corners = np.mean([np.mean(corner_tl), np.mean(corner_tr), np.mean(corner_bl), np.mean(corner_br)])
ratio = mean_corners / mean_center

print(f"Initial Uniformity Ratio: {ratio:.4f}")
with open("/tmp/initial_metrics.txt", "w") as f:
    f.write(f"initial_ratio={ratio}\n")
    f.write(f"initial_cv={np.std(img_data)/np.mean(img_data)*100}\n")
PYEOF

chown ga:ga /home/ga/Fiji_Data/raw/illumination_test/test_image.tif

# 4. Launch Fiji
echo "Launching Fiji..."
if ! pgrep -f "fiji" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
            echo "Fiji window detected"
            break
        fi
        sleep 1
    done
    sleep 5
    # Maximize
    DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="