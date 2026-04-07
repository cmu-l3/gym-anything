#!/bin/bash
echo "=== Setting up Generate CCD Variance Map task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AstroImages/noise_mapping"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Ensure HST sample data is unzipped and available
NGC_DIR="/opt/fits_samples/ngc6652"
if ls "$NGC_DIR"/*.zip 1> /dev/null 2>&1; then
    echo "Unzipping HST datasets..."
    cd "$NGC_DIR" && unzip -o *.zip > /dev/null 2>&1 || true
fi

# Locate the F555W image
ORIG_FITS=$(find "$NGC_DIR" -type f -name "*555wmos*.fits" | head -n 1)

if [ -z "$ORIG_FITS" ] || [ ! -f "$ORIG_FITS" ]; then
    echo "WARNING: NGC 6652 555wmos.fits not found. Creating a synthetic substitute for robustness."
    # If the file wasn't downloaded properly by the env install, we create a valid FITS to prevent task crash
    python3 -c "
import numpy as np
from astropy.io import fits
import os
data = np.random.normal(100, 10, (1000, 1000)).astype(np.float32)
fits.writeto('/tmp/synthetic_555w.fits', data, overwrite=True)
"
    ORIG_FITS="/tmp/synthetic_555w.fits"
fi

# Copy image to the working directory
cp "$ORIG_FITS" "$PROJECT_DIR/ngc6652_555w.fits"

# Create a parameter reference file for the agent
cat > "$PROJECT_DIR/parameters.txt" << 'EOF'
Detector Parameters for NGC 6652 F555W:
---------------------------------------
Gain = 7.12 e-/ADU
Read Noise = 5.24 e-

Instructions for Variance Map:
Variance = (Image_ADU * Gain) + (Read_Noise^2)

Instructions for Error Map:
Error = sqrt(max(0, Variance))
EOF

chown -R ga:ga "$PROJECT_DIR"

# Record task start time to detect "do nothing" gaming
date +%s > /tmp/task_start_timestamp

# Launch AstroImageJ (Empty state - agent must open file)
echo "Launching AstroImageJ..."
launch_astroimagej 120
sleep 2

WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Capture initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="