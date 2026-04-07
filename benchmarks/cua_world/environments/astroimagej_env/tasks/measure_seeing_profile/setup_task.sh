#!/bin/bash
set -euo pipefail

echo "=== Setting up measure_seeing_profile task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/AstroImages/raw
sudo -u ga mkdir -p /home/ga/AstroImages/measurements

# Clean up any pre-existing measurement files
rm -f /home/ga/AstroImages/measurements/background_stats.csv 2>/dev/null || true
rm -f /home/ga/AstroImages/measurements/seeing_profile.png 2>/dev/null || true
rm -f /home/ga/AstroImages/measurements/seeing_report.txt 2>/dev/null || true

# Locate and copy the FITS file
FITS_SRC="/opt/fits_samples/m12/Vcomb.fits"
FITS_DEST="/home/ga/AstroImages/raw/Vcomb.fits"

if [ -f "$FITS_SRC" ]; then
    echo "Copying M12 V-band FITS file to user directory..."
    cp "$FITS_SRC" "$FITS_DEST"
    chown ga:ga "$FITS_DEST"
else
    echo "WARNING: Source FITS file not found at $FITS_SRC"
    # Fallback to alternative sample if M12 is missing
    ALT_SRC=$(find /opt/fits_samples -name "*.fits" | head -1)
    if [ -n "$ALT_SRC" ]; then
        echo "Using fallback FITS file: $ALT_SRC"
        cp "$ALT_SRC" "$FITS_DEST"
        chown ga:ga "$FITS_DEST"
    else
        echo "ERROR: No FITS files available."
    fi
fi

# Ensure AstroImageJ is running
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/aij '$FITS_DEST' &"
    
    # Wait for the window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "AstroImageJ\|Vcomb"; then
            echo "AstroImageJ window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize and focus the main window
DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true

# Take an initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="