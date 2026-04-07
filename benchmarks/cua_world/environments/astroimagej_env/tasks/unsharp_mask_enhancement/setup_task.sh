#!/bin/bash
echo "=== Setting up Unsharp Mask Enhancement Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare directories
WORK_DIR="/home/ga/AstroImages/eagle_enhance"
OUT_DIR="$WORK_DIR/output"
rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

# 2. Copy the real HST FITS file (from pre-installed environment cache)
EAGLE_SRC="/opt/fits_samples/eagle_nebula/656nmos.fits"
EAGLE_DEST="$WORK_DIR/656nmos.fits"

if [ ! -f "$EAGLE_SRC" ]; then
    echo "WARNING: $EAGLE_SRC not found. Downloading dynamically..."
    wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/656nmos.zip" -O /tmp/eagle.zip
    unzip -p /tmp/eagle.zip > "$EAGLE_DEST"
else
    cp "$EAGLE_SRC" "$EAGLE_DEST"
fi

# 3. Create parameters file
cat > "$WORK_DIR/parameters.txt" << 'EOF'
=== Unsharp Mask Parameters ===
Target: Eagle Nebula (M16) Pillars of Creation
Filter: H-alpha (656 nm)

Parameters for AstroImageJ (Process > Filters > Unsharp Mask...):
- Gaussian Blur Radius (sigma): 5.0 pixels
- Mask Weight (0.1-0.9): 0.6

Goal: Enhance the fine filamentary structure at the tips of the pillars.
Save the result to: output/656nmos_unsharp.fits
Save your measurements to: output/enhancement_results.txt
EOF

chown -R ga:ga "$WORK_DIR"

# 4. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_timestamp

# 5. Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 120

# 6. Maximize window for visibility
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="