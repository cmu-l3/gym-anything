#!/bin/bash
echo "=== Setting up Evaluate Image Seeing Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure user directories exist
su - ga -c "mkdir -p ~/AstroImages/raw ~/AstroImages/measurements"

# Clean up any previous task files
rm -f /home/ga/AstroImages/measurements/seeing_data.csv 2>/dev/null
rm -f /home/ga/AstroImages/measurements/seeing_report.txt 2>/dev/null
rm -f /tmp/task_result.json 2>/dev/null

# Verify or download the Vcomb.fits file
FITS_DEST="/home/ga/AstroImages/raw/Vcomb.fits"
if [ ! -f "$FITS_DEST" ]; then
    echo "FITS file not found in home directory, copying from /opt/fits_samples..."
    if [ -f "/opt/fits_samples/m12/Vcomb.fits" ]; then
        cp /opt/fits_samples/m12/Vcomb.fits "$FITS_DEST"
    else
        echo "Downloading M12 Vcomb.fits directly..."
        wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/m12/Vcomb.zip" -O /tmp/Vcomb.zip
        unzip -o /tmp/Vcomb.zip -d /tmp/
        mv /tmp/Vcomb.fits "$FITS_DEST"
    fi
fi
chown ga:ga "$FITS_DEST"

# Start AstroImageJ if not running, passing the FITS file as an argument
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    echo "Starting AstroImageJ with Vcomb.fits..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh '$FITS_DEST' &"
    
    # Wait for the window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "AstroImageJ\|ImageJ\|Vcomb"; then
            echo "AstroImageJ window detected"
            break
        fi
        sleep 1
    done
fi

# Wait an additional moment for the UI and FITS image to fully render
sleep 5

# Maximize and focus the AstroImageJ window
DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Vcomb" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Vcomb" 2>/dev/null || true

# Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="