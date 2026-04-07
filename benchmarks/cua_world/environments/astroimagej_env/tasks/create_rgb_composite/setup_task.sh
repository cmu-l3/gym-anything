#!/bin/bash
set -euo pipefail

echo "=== Setting up Create RGB Composite Task ==="
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming (file creation checking)
date +%s > /tmp/task_start_time

# Define directories
SRC_DIR="/opt/fits_samples/eagle_nebula"
WORK_DIR="/home/ga/AstroImages/eagle_nebula"
OUT_DIR="/home/ga/AstroImages/processed"
OUT_FILE="$OUT_DIR/eagle_nebula_hubble_palette.png"

# Clean previous task artifacts
rm -f "$OUT_FILE" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Prepare working directories
mkdir -p "$WORK_DIR" "$OUT_DIR"

# Copy real Hubble Space Telescope data to the working directory
if [ -d "$SRC_DIR" ]; then
    echo "Copying source FITS files..."
    cp "$SRC_DIR/673nmos.fits" "$WORK_DIR/" || echo "Warning: 673nmos.fits missing"
    cp "$SRC_DIR/656nmos.fits" "$WORK_DIR/" || echo "Warning: 656nmos.fits missing"
    cp "$SRC_DIR/502nmos.fits" "$WORK_DIR/" || echo "Warning: 502nmos.fits missing"
else
    echo "ERROR: Source data directory $SRC_DIR not found!"
    exit 1
fi

# Ensure correct ownership
chown -R ga:ga /home/ga/AstroImages

# Launch AstroImageJ robustly using the environment utility
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize the AstroImageJ window
sleep 3
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Capture initial state screenshot as evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="