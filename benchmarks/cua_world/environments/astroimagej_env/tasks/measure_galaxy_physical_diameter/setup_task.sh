#!/bin/bash
echo "=== Setting up Measure Galaxy Physical Diameter Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create output directory
OUTPUT_DIR="/home/ga/AstroImages/uit_galaxy"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "/home/ga/AstroImages"

# Clear any previous task artifacts
rm -f "$OUTPUT_DIR/galaxy_diameter_report.json" 2>/dev/null || true
rm -f "$OUTPUT_DIR/measurement_overlay.jpg" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure the sample FITS file exists
FITS_FILE="/opt/fits_samples/uit_galaxy_sample.fits"
if [ ! -f "$FITS_FILE" ]; then
    echo "ERROR: UIT galaxy sample FITS file missing!"
    # Try to download it as a fallback
    mkdir -p /opt/fits_samples
    wget -q --timeout=30 "https://fits.gsfc.nasa.gov/samples/UITfuv2582gc.fits" -O "$FITS_FILE" 2>/dev/null || echo "Failed to download fallback FITS"
    chmod 644 "$FITS_FILE"
fi

# Start AstroImageJ (without loading the image - agent must do this)
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize AstroImageJ window
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot of the starting state
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="
echo ""
echo "Task: Measure the physical diameter of the M74 galaxy from UIT FUV data."
echo "FITS file: $FITS_FILE"
echo "Instructions:"
echo "1. Open the FITS file."
echo "2. Adjust contrast to reveal the spiral arms."
echo "3. Measure the major axis with the line tool."
echo "4. Save an overlay image to $OUTPUT_DIR/measurement_overlay.jpg"
echo "5. Calculate angular size and physical diameter."
echo "6. Save a JSON report to $OUTPUT_DIR/galaxy_diameter_report.json"