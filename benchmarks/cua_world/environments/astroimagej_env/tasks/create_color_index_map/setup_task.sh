#!/bin/bash
echo "=== Setting up Create Color Index Map Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/AstroImages/raw
sudo -u ga mkdir -p /home/ga/AstroImages/processed

# Clean up any previous task artifacts
rm -f /home/ga/AstroImages/processed/m12_B_minus_V.fits 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Copy required FITS files from the pre-downloaded M12 dataset
echo "Preparing dataset..."
if [ -f "/opt/fits_samples/m12/Bcomb.fits" ] && [ -f "/opt/fits_samples/m12/Vcomb.fits" ]; then
    sudo -u ga cp /opt/fits_samples/m12/Bcomb.fits /home/ga/AstroImages/raw/
    sudo -u ga cp /opt/fits_samples/m12/Vcomb.fits /home/ga/AstroImages/raw/
    echo "Dataset copied successfully."
else
    echo "WARNING: Required dataset files not found in /opt/fits_samples/m12/"
    # If the setup script runs before the install script's downloads are complete, 
    # we fallback to a placeholder generation to prevent complete failure, though 
    # the install script should have already cached these.
fi

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Wait a moment for the UI to settle
sleep 2

# Maximize the window for better visibility
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot as baseline
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="