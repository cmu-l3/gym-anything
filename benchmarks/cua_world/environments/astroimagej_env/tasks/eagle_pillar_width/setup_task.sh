#!/bin/bash
echo "=== Setting up Eagle Nebula Pillar Width task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create working directory
PROJECT_DIR="/home/ga/AstroImages/eagle_pillar"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Copy real HST Eagle Nebula H-alpha FITS file
EAGLE_SRC="/opt/fits_samples/eagle_nebula/656nmos.fits"
EAGLE_ZIP="/opt/fits_samples/eagle_nebula/656nmos.zip"

if [ -f "$EAGLE_SRC" ]; then
    cp "$EAGLE_SRC" "$PROJECT_DIR/656nmos.fits"
elif [ -f "$EAGLE_ZIP" ]; then
    unzip -q "$EAGLE_ZIP" -d "$PROJECT_DIR"
else
    echo "WARNING: Eagle Nebula 656nm file not found in cache. Creating placeholder for resilience."
    # We still try to let the script proceed, the agent might fail but the env won't crash
    touch "$PROJECT_DIR/656nmos.fits"
fi

# Create measurement guide
TARGET_Y=600
cat > "$PROJECT_DIR/measurement_guide.txt" << EOF
Measurement Guide for Eagle Nebula Pillar

Target: The tallest Pillar of Creation (typically the leftmost major pillar)
Target Row: Y = $TARGET_Y (allowable tolerance +/- 30 pixels)

Instructions:
Draw a horizontal line across the pillar at approximately this Y-coordinate.
The pillar appears as a dark absorption feature against the bright background.
Measure the FWHM (Full Width at Half Maximum) of this dark trough in pixels.
EOF

# Create plate scale info
PLATE_SCALE=0.1
cat > "$PROJECT_DIR/plate_scale_info.txt" << EOF
Plate Scale Information

Telescope: HST
Instrument: WFPC2 (Mosaic)
Filter: F656N (H-alpha)

Effective Plate Scale: $PLATE_SCALE arcseconds per pixel
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Compute ground truth directly from the data
python3 << PYEOF
import json
import os
import numpy as np

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

gt = {
    "target_y": $TARGET_Y,
    "plate_scale": $PLATE_SCALE,
    "fallback_used": False,
    "width_pixels": 75.0,  # Fallback default
    "width_arcsec": 7.5    # Fallback default
}

filepath = "$PROJECT_DIR/656nmos.fits"

if HAS_ASTROPY and os.path.exists(filepath) and os.path.getsize(filepath) > 1024:
    try:
        data = fits.getdata(filepath)
        # Handle 3D or multiple extensions safely
        if data.ndim > 2:
            data = data[0]
            
        # The pillar is roughly in the left-center of the full 1600x1600 mosaic
        # We extract the row
        row = data[$TARGET_Y, :]
        
        # We look at X between 400 and 1000 where the tallest pillar resides
        segment = row[400:1000]
        
        # The pillar is an absorption feature (dark). We invert it to find FWHM of the "dip"
        inverted = np.max(segment) - segment
        
        # Find the peak of the inverted signal (the deepest part of the pillar)
        peak_idx = np.argmax(inverted)
        peak_val = inverted[peak_idx]
        half_max = peak_val / 2.0
        
        # Measure FWHM by walking left and right
        left_idx = peak_idx
        while left_idx > 0 and inverted[left_idx] > half_max:
            left_idx -= 1
            
        right_idx = peak_idx
        while right_idx < len(segment) - 1 and inverted[right_idx] > half_max:
            right_idx += 1
            
        fwhm_pixels = right_idx - left_idx
        
        # Sanity check the measurement (should be between 20 and 200 pixels)
        if 20 < fwhm_pixels < 200:
            gt["width_pixels"] = float(fwhm_pixels)
            gt["width_arcsec"] = float(fwhm_pixels * $PLATE_SCALE)
            gt["fallback_used"] = False
        else:
            gt["fallback_used"] = True
            
    except Exception as e:
        print(f"Error computing ground truth: {e}")
        gt["fallback_used"] = True

with open("/tmp/pillar_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)
PYEOF

chmod 644 /tmp/pillar_ground_truth.json

# Start AstroImageJ (no image loaded, agent must do it)
echo "Starting AstroImageJ..."
launch_astroimagej 120

# Maximize the AstroImageJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="