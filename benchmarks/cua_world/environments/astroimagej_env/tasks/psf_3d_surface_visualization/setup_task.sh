#!/bin/bash
echo "=== Setting up psf_3d_surface_visualization task ==="

source /workspace/scripts/task_utils.sh

# Prepare directories
sudo -u ga mkdir -p /home/ga/AstroImages/raw
sudo -u ga mkdir -p /home/ga/AstroImages/processed

# Copy the sample file if not already there
if [ ! -f /home/ga/AstroImages/raw/hst_wfpc2_sample.fits ]; then
    if [ -f /opt/fits_samples/hst_wfpc2_sample.fits ]; then
        cp /opt/fits_samples/hst_wfpc2_sample.fits /home/ga/AstroImages/raw/
        chown ga:ga /home/ga/AstroImages/raw/hst_wfpc2_sample.fits
    fi
fi

# Clean up any previous runs
rm -f /home/ga/AstroImages/processed/psf_crop.fits
rm -f /home/ga/AstroImages/processed/psf_surface.png
rm -f /home/ga/AstroImages/processed/psf_stats.txt
rm -f /tmp/task_result.json

# Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt

# Launch AstroImageJ
launch_astroimagej 120
sleep 2

# Maximize AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="