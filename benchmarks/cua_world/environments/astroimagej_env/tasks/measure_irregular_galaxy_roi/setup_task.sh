#!/bin/bash
echo "=== Setting up Irregular Galaxy Core Photometry Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create project directories
WORK_DIR="/home/ga/AstroImages/uit_galaxy"
MEASURE_DIR="/home/ga/AstroImages/measurements"
rm -rf "$WORK_DIR" "$MEASURE_DIR"
mkdir -p "$WORK_DIR" "$MEASURE_DIR"

# Copy the real UIT FITS sample to the working directory
if [ -f "/opt/fits_samples/uit_galaxy_sample.fits" ]; then
    cp "/opt/fits_samples/uit_galaxy_sample.fits" "$WORK_DIR/"
    echo "FITS file copied to $WORK_DIR/"
else
    echo "ERROR: uit_galaxy_sample.fits not found in /opt/fits_samples/"
    exit 1
fi

chown -R ga:ga /home/ga/AstroImages

# Clean up any potential artifacts
rm -f /tmp/task_result.json /tmp/aij_final_screenshot.png 2>/dev/null

# Launch AstroImageJ (do not pre-load the image, agent must do it)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize AstroImageJ window for the agent
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="