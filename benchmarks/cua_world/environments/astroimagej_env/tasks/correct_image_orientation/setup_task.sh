#!/bin/bash
set -euo pipefail

echo "=== Setting up Image Orientation Correction Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Set up task directories
WORK_DIR="/home/ga/AstroImages/orientation"
CORRECTED_DIR="$WORK_DIR/corrected"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$CORRECTED_DIR"

# Locate the NGC 6652 sample FITS file
NGC_DIR="/opt/fits_samples/ngc6652"
FITS_FILE="$WORK_DIR/ngc6652_555w.fits"

# Use Python to extract/copy the FITS file and compute the ground truth
python3 << 'PYEOF'
import os
import shutil
import glob
import json
import math
import subprocess
try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

NGC_DIR = "/opt/fits_samples/ngc6652"
WORK_DIR = "/home/ga/AstroImages/orientation"
FITS_DEST = os.path.join(WORK_DIR, "ngc6652_555w.fits")

# Find the V-band (555w) FITS file
fits_files = glob.glob(os.path.join(NGC_DIR, "**/*555*.fits"), recursive=True) + \
             glob.glob(os.path.join(NGC_DIR, "**/*555*.fit"), recursive=True)

if not fits_files:
    # Try unzipping if not extracted
    zips = glob.glob(os.path.join(NGC_DIR, "*555*.zip"))
    for z in zips:
        subprocess.run(["unzip", "-o", z, "-d", NGC_DIR], check=False)
    fits_files = glob.glob(os.path.join(NGC_DIR, "**/*555*.fits"), recursive=True)

if not fits_files:
    # Fallback to any FITS file in the directory
    fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True)

if not fits_files:
    print(f"ERROR: No FITS files found in {NGC_DIR}")
    import sys; sys.exit(1)

source_fits = fits_files[0]
print(f"Copying {source_fits} to {FITS_DEST}")
shutil.copy2(source_fits, FITS_DEST)

# Compute ground truth from the FITS header
ground_truth = {
    "file_prepared": True,
    "cd_matrix_found": False,
    "position_angle_deg": 0.0,
    "cd1_1": 0.0, "cd1_2": 0.0,
    "cd2_1": 0.0, "cd2_2": 0.0
}

if HAS_ASTROPY:
    with fits.open(FITS_DEST) as hdul:
        hdr = hdul[0].header
        cd11 = hdr.get('CD1_1', hdr.get('CDELT1', 0.0))
        cd12 = hdr.get('CD1_2', 0.0)
        cd21 = hdr.get('CD2_1', 0.0)
        cd22 = hdr.get('CD2_2', hdr.get('CDELT2', 0.0))
        
        ground_truth["cd1_1"] = cd11
        ground_truth["cd1_2"] = cd12
        ground_truth["cd2_1"] = cd21
        ground_truth["cd2_2"] = cd22
        
        if cd11 != 0 or cd12 != 0 or cd21 != 0 or cd22 != 0:
            ground_truth["cd_matrix_found"] = True
            # Compute Position Angle of the Y-axis (North)
            # Standard WCS: xi = CD1_1*x + CD1_2*y; eta = CD2_1*x + CD2_2*y
            # +Y axis vector is (CD1_2, CD2_2)
            # Angle of +Y from North (eta) towards East (xi) is atan2(CD1_2, CD2_2)
            pa_rad = math.atan2(cd12, cd22)
            pa_deg = math.degrees(pa_rad)
            ground_truth["position_angle_deg"] = pa_deg

with open('/tmp/orientation_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)
print("Ground truth saved.")
PYEOF

# Create the hints file
cat > "$WORK_DIR/orientation_hints.txt" << 'EOF'
HINTS FOR IMAGE ORIENTATION CORRECTION

Astronomical Standard Orientation:
- North should point UP (towards the top edge of the image, +Y)
- East should point LEFT (towards the left edge of the image, -X)

How to determine current orientation from FITS WCS keywords:
1. Open the FITS Header (Image > Show Info or Edit > FITS Header).
2. Look for the CD matrix keywords: CD1_1, CD1_2, CD2_1, CD2_2.
   (These encode both the pixel scale and the rotation).
3. The Position Angle (PA) of the image's Y-axis (North direction) can be 
   computed mathematically from the CD matrix.
   Formula: PA = atan2(CD1_2, CD2_2)  [using typical math library atan2(y, x) 
   where y is the East-West component and x is the North-South component]
   Convert the result from radians to degrees!

How to correct the orientation:
1. If the current North is at angle PA (in degrees), you need to rotate 
   the image by -PA to bring North straight up.
2. Use AstroImageJ's rotate tool: Image > Transform > Rotate.
3. Note: AstroImageJ rotates COUNTER-CLOCKWISE for positive angles.

For this task, determining the approximate angle and applying the rotation 
is sufficient. Don't forget to save the rotated FITS and create the report!
EOF

chown -R ga:ga "$WORK_DIR"
date +%s > /tmp/task_start_time

# Launch AstroImageJ
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start AIJ in the background
echo "Launching AstroImageJ..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx2g' /usr/local/bin/aij > /tmp/astroimagej_ga.log 2>&1" &

# Wait for AstroImageJ to start
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|AstroImageJ"; then
        echo "AstroImageJ window detected."
        break
    fi
    sleep 1
done

# Maximize the window for better agent visibility
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|AstroImageJ" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="