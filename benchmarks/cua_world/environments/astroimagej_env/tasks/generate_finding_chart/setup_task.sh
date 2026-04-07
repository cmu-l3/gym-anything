#!/bin/bash
echo "=== Setting up generate_finding_chart task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and have proper permissions
mkdir -p /home/ga/AstroImages/raw/m12
mkdir -p /home/ga/AstroImages/processed
chown -R ga:ga /home/ga/AstroImages

# Copy the real M12 V-band sample data into the working directory
if [ -f "/opt/fits_samples/m12/Vcomb.fits" ]; then
    cp /opt/fits_samples/m12/Vcomb.fits /home/ga/AstroImages/raw/m12/Vcomb.fits
    chown ga:ga /home/ga/AstroImages/raw/m12/Vcomb.fits
else
    echo "WARNING: Original Vcomb.fits sample not found in /opt/fits_samples"
fi

# Clean up any potential artifacts from previous runs
rm -f /home/ga/AstroImages/processed/m12_core_crop.fits
rm -f /home/ga/AstroImages/processed/m12_core_finding_chart.png

# Ensure AstroImageJ is running
if ! is_aij_running; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"
    
    # Wait for the main window to appear
    wait_for_window "ImageJ\|AstroImageJ\|AIJ" 30
    sleep 3
fi

# Focus and maximize AstroImageJ main window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any stray dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture the initial state screenshot showing the clean environment
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="