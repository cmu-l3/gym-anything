#!/bin/bash
echo "=== Setting up create_hubble_palette_composite task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/AstroImages/raw/eagle
mkdir -p /home/ga/AstroImages/processed

# Copy Eagle Nebula FITS files to user directory
if [ -d "/opt/fits_samples/eagle_nebula" ]; then
    cp /opt/fits_samples/eagle_nebula/*.fits /home/ga/AstroImages/raw/eagle/ 2>/dev/null || true
    echo "Eagle Nebula FITS files copied to ~/AstroImages/raw/eagle/"
else
    echo "WARNING: /opt/fits_samples/eagle_nebula not found. FITS files may be missing!"
fi

# Ensure correct permissions
chown -R ga:ga /home/ga/AstroImages

# Remove any existing output to ensure a clean state
rm -f /home/ga/AstroImages/processed/eagle_hubble_palette.png

# Launch AstroImageJ using utility function
launch_astroimagej 60

# Maximize and focus the window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="