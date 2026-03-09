#!/bin/bash
echo "=== Setting up apply_pseudocolor_to_raster task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# -------------------------------------------------------------------
# Generate Synthetic Grayscale Raster (elevation.tif)
# -------------------------------------------------------------------
echo "Generating synthetic elevation raster..."

# Use python to generate a gradient TIFF
cat > /tmp/generate_raster.py << 'PYEOF'
import numpy as np
from PIL import Image
import os

# Create a 512x512 gradient
width, height = 512, 512
x = np.linspace(0, 255, width)
y = np.linspace(0, 255, height)
X, Y = np.meshgrid(x, y)
# simple diagonal gradient
gradient = (X + Y) / 2
gradient = gradient.astype(np.uint8)

img = Image.fromarray(gradient, mode='L')
output_path = '/home/ga/gvsig_data/elevation.tif'
img.save(output_path)
print(f"Created {output_path}")
PYEOF

# Run generation (ensure PIL is installed, it's in the env spec)
python3 /tmp/generate_raster.py || {
    echo "Python generation failed, trying convert (ImageMagick)..."
    convert -size 512x512 gradient:black-white -depth 8 /home/ga/gvsig_data/elevation.tif
}

# Ensure file exists and permissions
if [ -f "/home/ga/gvsig_data/elevation.tif" ]; then
    echo "Raster generated successfully."
    chown ga:ga /home/ga/gvsig_data/elevation.tif
else
    echo "ERROR: Failed to generate raster!"
    exit 1
fi

# Clean up previous exports
rm -f /home/ga/gvsig_data/exports/colored_elevation.png

# -------------------------------------------------------------------
# Launch gvSIG
# -------------------------------------------------------------------
echo "Launching gvSIG Desktop..."
kill_gvsig

# Launch with empty project
launch_gvsig ""

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="