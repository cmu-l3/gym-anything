#!/bin/bash
echo "=== Setting up Export Publication Figure Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create working directory
PUB_DIR="/home/ga/AstroImages/publication"
mkdir -p "$PUB_DIR"
chown ga:ga "$PUB_DIR"

# Clean up any previous attempts
rm -f "$PUB_DIR/eagle_figure.png" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Verify source FITS file exists (downloaded during environment install)
SOURCE_FITS="/opt/fits_samples/eagle_nebula/656nmos.fits"
if [ ! -f "$SOURCE_FITS" ]; then
    echo "ERROR: Source FITS file not found at $SOURCE_FITS"
    echo "Ensure environment installation script ran correctly."
    exit 1
fi

# Write a quick reference file for the agent/user
cat > "$PUB_DIR/figure_requirements.txt" << EOF
Publication Figure Requirements:
- Source FITS: /opt/fits_samples/eagle_nebula/656nmos.fits
- Plate Scale: 0.1 arcsec/pixel
- Image Type: 8-bit
- Look-Up Table (LUT): Fire
- Scale Bar: 30 arcsec (White, Lower Right)
- Output: ~/AstroImages/publication/eagle_figure.png
EOF
chown ga:ga "$PUB_DIR/figure_requirements.txt"

# Kill any existing AstroImageJ instances
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize and focus the window
sleep 3
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized."
fi

# Take initial screenshot to document clean state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="