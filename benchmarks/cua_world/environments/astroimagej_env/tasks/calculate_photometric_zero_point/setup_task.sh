#!/bin/bash
set -e
echo "=== Setting up Calculate Photometric Zero Point Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
TASK_DIR="/home/ga/AstroImages/zero_point"
SOURCE_DIR="/opt/fits_samples/m12"
M12_IMAGE="$SOURCE_DIR/Vcomb.fits"

# Clean up previous runs
rm -rf "$TASK_DIR"
mkdir -p "$TASK_DIR"
chown ga:ga "$TASK_DIR"

# Record task start time
date +%s > /tmp/task_start_time

# 1. Prepare Image
if [ -f "$M12_IMAGE" ]; then
    cp "$M12_IMAGE" "$TASK_DIR/M12_V.fits"
    echo "Copied M12 V-band image."
else
    echo "ERROR: Source image not found at $M12_IMAGE"
    exit 1
fi

# 2. Generate Standard Star List & Ground Truth
# We use a python script to dynamically find real stars in the image,
# measure their flux, and assign standard magnitudes based on a RANDOM ZP.
# This makes it impossible for the agent to game the expected value.
cat > /tmp/gen_zp_data.py << 'EOF'
import sys
import numpy as np
from astropy.io import fits
from scipy.ndimage import maximum_filter
import math
import random

try:
    # Generate a random true ZP for this session to prevent gaming
    TRUE_ZP = round(random.uniform(25.0, 28.0), 2)
    print(f"Generated TRUE_ZP: {TRUE_ZP}")
    
    hdul = fits.open('/home/ga/AstroImages/zero_point/M12_V.fits')
    data = hdul[0].data
    hdul.close()

    # Find peaks to identify stars
    threshold = np.mean(data) + 3 * np.std(data)
    local_max = maximum_filter(data, size=20) == data
    background = (data > threshold)
    detected = local_max & background
    
    y_coords, x_coords = np.where(detected)
    
    selected_stars = []
    h, w = data.shape
    
    # Select 5 isolated, bright stars
    for y, x in zip(y_coords, x_coords):
        if x < 50 or x > w-50 or y < 50 or y > h-50: continue
        
        # Check isolation
        is_isolated = True
        for sy, sx in zip(y_coords, x_coords):
            if sy==y and sx==x: continue
            if math.sqrt((x-sx)**2 + (y-sy)**2) < 40:
                is_isolated = False
                break
        
        if is_isolated:
            selected_stars.append((x, y))
            if len(selected_stars) >= 5: break
            
    if len(selected_stars) < 5:
        # Fallback coordinates if peak finding fails
        selected_stars = [(300, 300), (400, 400), (500, 500), (600, 600), (700, 700)]
    
    output_lines = ["# ID  X_Pixel  Y_Pixel  Standard_V_Mag"]
    
    for i, (x, y) in enumerate(selected_stars):
        # Perform simple aperture photometry (Radius=15, In=20, Out=30)
        Y, X = np.ogrid[:h, :w]
        dist = np.sqrt((X - x)**2 + (Y - y)**2)
        mask_ap = dist <= 15
        mask_annulus = (dist >= 20) & (dist <= 30)
        
        flux = np.sum(data[mask_ap])
        sky_median = np.median(data[mask_annulus])
        n_pix = np.sum(mask_ap)
        
        net_counts = flux - (sky_median * n_pix)
        
        if net_counts <= 0: 
            net_counts = 1000 # Fallback positive value
            
        # ZP = V + 2.5*log10(counts) => V = ZP - 2.5*log10(counts)
        inst_mag = -2.5 * math.log10(net_counts)
        std_mag = inst_mag + TRUE_ZP
        
        output_lines.append(f"{i+1}     {int(x)}     {int(y)}      {std_mag:.3f}")
        
    # Write catalog file
    with open('/home/ga/AstroImages/zero_point/standard_stars.txt', 'w') as f:
        f.write("\n".join(output_lines))
        
    # Write Ground Truth for the verifier
    with open('/tmp/zp_ground_truth.txt', 'w') as f:
        f.write(str(TRUE_ZP))
        
    print("Standard stars generated successfully.")

except Exception as e:
    print(f"Error generating data: {e}")
    sys.exit(1)
EOF

python3 /tmp/gen_zp_data.py

chown ga:ga "$TASK_DIR/M12_V.fits"
chown ga:ga "$TASK_DIR/standard_stars.txt"
chmod 644 /tmp/zp_ground_truth.txt

# 3. Setup AstroImageJ launch
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh" &
sleep 10

# Maximize AIJ
DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true

# Open the image using xdotool
DISPLAY=:1 xdotool key ctrl+o
sleep 1
DISPLAY=:1 xdotool type "$TASK_DIR/M12_V.fits"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 4

# Take initial screenshot showing AIJ and the opened image
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="