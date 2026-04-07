#!/bin/bash
echo "=== Setting up Galaxy Morphological Asymmetry Task ==="

source /workspace/scripts/task_utils.sh

# Set up the directory structure
mkdir -p /home/ga/AstroImages/raw
mkdir -p /home/ga/AstroImages/morphology

# Copy the actual UIT sample image to the working directory
cp /opt/fits_samples/uit_galaxy_sample.fits /home/ga/AstroImages/raw/
chown -R ga:ga /home/ga/AstroImages

# Clean any residual artifacts
rm -f /home/ga/AstroImages/morphology/asymmetry_residual.fits
rm -f /home/ga/AstroImages/morphology/asymmetry_stats.txt
rm -f /tmp/task_result.json
rm -f /tmp/asymmetry_ground_truth.json

# Record initial timestamp
date +%s > /tmp/task_start_timestamp

# Launch AstroImageJ in a clean state (No images loaded initially)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize AstroImageJ for agent visibility
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot for the trajectory
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="