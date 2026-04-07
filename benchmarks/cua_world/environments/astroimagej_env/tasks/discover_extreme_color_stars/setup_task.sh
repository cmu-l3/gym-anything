#!/bin/bash
echo "=== Setting up Discover Extreme Color Stars Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create clean working directory
PROJECT_DIR="/home/ga/AstroImages/color_search"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Copy FITS files to working directory
if [ -f "/opt/fits_samples/m12/Vcomb.fits" ] && [ -f "/opt/fits_samples/m12/Bcomb.fits" ]; then
    cp /opt/fits_samples/m12/Vcomb.fits "$PROJECT_DIR/"
    cp /opt/fits_samples/m12/Bcomb.fits "$PROJECT_DIR/"
else
    echo "ERROR: Required FITS files not found in cache. Agent may fail."
fi

# Set proper permissions
chown -R ga:ga "$PROJECT_DIR"

# Launch AstroImageJ
launch_astroimagej 120

# Maximize the AstroImageJ window
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot showing clean state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="