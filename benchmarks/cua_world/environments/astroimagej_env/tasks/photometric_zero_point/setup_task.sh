#!/bin/bash
echo "=== Setting up photometric_zero_point task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Clean any existing artifacts to prevent gaming
rm -f /home/ga/AstroImages/measurements/m12_photometry.csv 2>/dev/null
rm -f /home/ga/AstroImages/processed/zero_point_report.json 2>/dev/null
sudo -u ga mkdir -p /home/ga/AstroImages/measurements/
sudo -u ga mkdir -p /home/ga/AstroImages/processed/

# Ensure VLT Messier 12 data is available
if [ ! -f "/opt/fits_samples/m12/Vcomb.fits" ] || [ ! -f "/opt/fits_samples/m12/m12_B_V.xls" ]; then
    echo "Downloading VLT Messier 12 data..."
    mkdir -p /opt/fits_samples/m12
    wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/m12/Vcomb.zip" -O /opt/fits_samples/m12/Vcomb.zip || true
    if [ -f "/opt/fits_samples/m12/Vcomb.zip" ]; then
        cd /opt/fits_samples/m12 && unzip -o Vcomb.zip
    fi
    wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/m12/m12_B_V.xls" -O /opt/fits_samples/m12/m12_B_V.xls || true
fi

# Set permissions
chmod -R 755 /opt/fits_samples/m12/

# Start AstroImageJ if not running
if ! is_aij_running; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"
    
    # Wait for window
    wait_for_window "ImageJ\|AstroImageJ\|AIJ" 30
fi

# Maximize AIJ
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="