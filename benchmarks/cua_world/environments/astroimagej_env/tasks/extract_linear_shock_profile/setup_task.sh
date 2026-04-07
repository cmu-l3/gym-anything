#!/bin/bash
echo "=== Setting up extract_linear_shock_profile task ==="

# Record task start time
date +%s > /tmp/task_start_time

# Ensure directories exist with correct permissions
sudo -u ga mkdir -p /home/ga/AstroImages/raw
sudo -u ga mkdir -p /home/ga/AstroImages/measurements

# Clean any artifacts from previous runs
rm -f /home/ga/AstroImages/measurements/shock_profile.csv
rm -f /home/ga/AstroImages/measurements/plot_screenshot.png

# Prepare the FITS file
FITS_TARGET="/home/ga/AstroImages/raw/673nmos.fits"
if [ ! -f "$FITS_TARGET" ]; then
    if [ -f "/opt/fits_samples/eagle_nebula/673nmos.fits" ]; then
        cp /opt/fits_samples/eagle_nebula/673nmos.fits "$FITS_TARGET"
    else
        echo "Warning: FITS file not found in /opt, generating synthetic fallback..."
        python3 -c "import numpy as np; from astropy.io import fits; data=np.random.normal(100, 10, (1000,1000)); data[600:700, 400:800] += 50.0; fits.writeto('$FITS_TARGET', data, overwrite=True)"
    fi
    chown ga:ga "$FITS_TARGET"
fi

# Ensure AstroImageJ is running
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/aij &"
    sleep 5
fi

# Wait for application window to appear
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "AstroImageJ\|ImageJ"; then
        echo "AstroImageJ window detected."
        break
    fi
    sleep 1
done

# Maximize and focus the application window
DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true
sleep 1

# Take an initial screenshot for baseline comparison
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="