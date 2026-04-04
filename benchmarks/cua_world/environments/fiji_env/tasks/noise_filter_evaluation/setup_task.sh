#!/bin/bash
echo "=== Setting up Noise Filter Evaluation Task ==="

# 1. Create directories
mkdir -p /home/ga/Fiji_Data/raw/filter_test
mkdir -p /home/ga/Fiji_Data/results/filter_comparison

# 2. Clean previous results
rm -f /home/ga/Fiji_Data/results/filter_comparison/*
rm -f /tmp/filter_task_result.json

# 3. Create a synthetic noisy image ensures consistency and availability
# We use Python to generate a noisy image to guarantee the task is playable without external downloads
cat > /tmp/create_noisy_image.py << 'PYEOF'
import numpy as np
from PIL import Image
import os

# Create a synthetic image with features and noise
width, height = 512, 512
image = np.zeros((height, width), dtype=np.float32)

# Add some "cells" (bright spots)
np.random.seed(42)
for _ in range(20):
    x, y = np.random.randint(0, width), np.random.randint(0, height)
    r = np.random.randint(10, 30)
    y_grid, x_grid = np.ogrid[-y:height-y, -x:width-x]
    mask = x_grid**2 + y_grid**2 <= r**2
    image[mask] = 150 + np.random.randint(-20, 20)

# Add background intensity
image += 30

# Add Gaussian noise
noise = np.random.normal(0, 25, image.shape)
noisy_image = image + noise
noisy_image = np.clip(noisy_image, 0, 255).astype(np.uint8)

# Save
output_path = "/home/ga/Fiji_Data/raw/filter_test/test_image.tif"
Image.fromarray(noisy_image).save(output_path)
print(f"Created noisy image at {output_path}")

# Calculate baseline stats for reference
mean = np.mean(noisy_image)
std = np.std(noisy_image)
snr = mean / std if std > 0 else 0
print(f"Baseline - Mean: {mean:.2f}, Std: {std:.2f}, SNR: {snr:.2f}")

with open("/tmp/baseline_stats.txt", "w") as f:
    f.write(f"{mean},{std},{snr}")
PYEOF

python3 /tmp/create_noisy_image.py

# 4. Set permissions
chown -R ga:ga /home/ga/Fiji_Data
chmod -R 755 /home/ga/Fiji_Data

# 5. Record start time
date +%s > /tmp/task_start_time

# 6. Launch Fiji
echo "Launching Fiji..."
pkill -f "fiji" || true
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &

# Wait for Fiji window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="