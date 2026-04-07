#!/bin/bash
echo "=== Setting up galaxy_fft_bandpass_filtering task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/AstroImages/raw
mkdir -p /home/ga/AstroImages/processed

# Clean up any residual files from previous runs
rm -f /home/ga/AstroImages/processed/uit_bandpass_filtered.fits
rm -f /home/ga/AstroImages/processed/filter_report.txt

# Copy the real FITS file sample to the working directory
if [ -f "/opt/fits_samples/uit_galaxy_sample.fits" ]; then
    cp /opt/fits_samples/uit_galaxy_sample.fits /home/ga/AstroImages/raw/uit_galaxy_sample.fits
else
    echo "WARNING: /opt/fits_samples/uit_galaxy_sample.fits not found!"
fi

# Set proper ownership
chown -R ga:ga /home/ga/AstroImages

# Launch AstroImageJ
launch_astroimagej 120
sleep 2

# Maximize AIJ window for full visibility
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="