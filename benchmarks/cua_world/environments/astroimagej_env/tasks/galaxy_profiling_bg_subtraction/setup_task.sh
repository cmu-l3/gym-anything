#!/bin/bash
echo "=== Setting up Galaxy Profiling Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/AstroImages/raw
sudo -u ga mkdir -p /home/ga/AstroImages/processed
sudo -u ga mkdir -p /home/ga/AstroImages/measurements

# Clear any previous outputs
rm -f /home/ga/AstroImages/measurements/background_measure.csv 2>/dev/null || true
rm -f /home/ga/AstroImages/measurements/galaxy_profile.csv 2>/dev/null || true
rm -f /home/ga/AstroImages/processed/uit_galaxy_bg_subtracted.fits 2>/dev/null || true

# Ensure raw file is present
RAW_FILE="/home/ga/AstroImages/raw/uit_galaxy_sample.fits"
if [ ! -f "$RAW_FILE" ]; then
    echo "Copying sample file..."
    cp /opt/fits_samples/uit_galaxy_sample.fits "$RAW_FILE" 2>/dev/null || true
    chown ga:ga "$RAW_FILE"
fi

# Launch AstroImageJ
launch_astroimagej 60

# Ensure window is maximized
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="