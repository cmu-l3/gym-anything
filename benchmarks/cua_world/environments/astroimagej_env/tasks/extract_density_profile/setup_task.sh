#!/bin/bash
set -euo pipefail

echo "=== Setting up extract_density_profile task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/AstroImages/raw/ngc6652
mkdir -p /home/ga/AstroImages/measurements

# Copy the required FITS file from the installation cache to the working directory
if [ -f "/opt/fits_samples/ngc6652/555wmos.fits" ]; then
    cp /opt/fits_samples/ngc6652/555wmos.fits /home/ga/AstroImages/raw/ngc6652/
    echo "FITS file copied successfully."
else
    echo "WARNING: /opt/fits_samples/ngc6652/555wmos.fits not found. The environment might be missing the sample."
fi

# Remove any pre-existing output files to prevent gaming
rm -f /home/ga/AstroImages/measurements/profile.txt
rm -f /home/ga/AstroImages/measurements/core_report.json

# Fix permissions
chown -R ga:ga /home/ga/AstroImages

# Launch AstroImageJ for the agent to save them time
if ! pgrep -f "astroimagej\|AstroImageJ\|aij" > /dev/null; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"
    
    # Wait for the window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ"; then
            echo "AstroImageJ window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize and focus AstroImageJ
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true

# Take initial screenshot as evidence of starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="