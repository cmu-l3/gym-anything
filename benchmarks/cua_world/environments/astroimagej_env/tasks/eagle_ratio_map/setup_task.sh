#!/bin/bash
echo "=== Setting up Eagle Nebula Ratio Map Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Prepare working directory
WORK_DIR="/home/ga/AstroImages/eagle_ratio"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Source directory from installation cache
SRC_DIR="/opt/fits_samples/eagle_nebula"

# Download fallback if not present in cache
if [ ! -f "$SRC_DIR/656nmos.fits" ] || [ ! -f "$SRC_DIR/673nmos.fits" ]; then
    echo "Downloading Eagle Nebula dataset..."
    mkdir -p "$SRC_DIR"
    wget -q -O "$SRC_DIR/656nmos.zip" "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/656nmos.zip"
    wget -q -O "$SRC_DIR/673nmos.zip" "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/673nmos.zip"
    unzip -q -o "$SRC_DIR/656nmos.zip" -d "$SRC_DIR" 2>/dev/null || true
    unzip -q -o "$SRC_DIR/673nmos.zip" -d "$SRC_DIR" 2>/dev/null || true
fi

# Copy FITS files to working directory
cp "$SRC_DIR/656nmos.fits" "$WORK_DIR/"
cp "$SRC_DIR/673nmos.fits" "$WORK_DIR/"

# Compute ground truth mathematically and save to a hidden file
python3 << 'EOF'
import json, os
import numpy as np
try:
    from astropy.io import fits
    f656 = '/home/ga/AstroImages/eagle_ratio/656nmos.fits'
    f673 = '/home/ga/AstroImages/eagle_ratio/673nmos.fits'
    
    d_ha = fits.getdata(f656).astype(float)
    d_sii = fits.getdata(f673).astype(float)
    
    # Calculate ratio, ignoring divide by zero issues
    with np.errstate(divide='ignore', invalid='ignore'):
        ratio = d_sii / d_ha
        
    valid = ratio[np.isfinite(ratio)]
    
    gt = {
        'shape': list(d_ha.shape),
        'gt_median': float(np.median(valid)),
        'gt_std': float(np.std(valid)),
        'gt_min': float(np.min(valid)),
        'gt_max': float(np.max(valid)),
        'ha_median': float(np.median(d_ha)),
        'sii_median': float(np.median(d_sii))
    }
except Exception as e:
    gt = {'error': str(e)}

with open('/tmp/eagle_ratio_ground_truth.json', 'w') as f:
    json.dump(gt, f)
EOF

# Create agent instructions note
cat > "$WORK_DIR/INSTRUCTIONS.txt" << 'EOF'
TASK GOAL: Create a [SII]/H-alpha emission line ratio map.

Steps:
1. Open both FITS images in AstroImageJ (656nmos.fits and 673nmos.fits).
2. Divide the [SII] image (673nmos) by the H-alpha image (656nmos) using the Image Calculator. Use 32-bit float output.
3. Save the resulting image as 'sii_ha_ratio.fits' in this folder.
4. Measure the image statistics of the ratio map.
5. Save the statistics (min, max, median, standard deviation) in 'ratio_statistics.txt' in this folder.
EOF

chown -R ga:ga "$WORK_DIR"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Launch AstroImageJ
echo "Starting AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

export DISPLAY=:1
xhost +local: 2>/dev/null || true
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' /usr/local/bin/aij > /tmp/astroimagej_ga.log 2>&1" &

# Wait for application to start
sleep 8

# Maximize and focus Window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "AstroImageJ\|ImageJ" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
echo "Setup complete."