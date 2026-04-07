#!/bin/bash
echo "=== Setting up Star/Galaxy Separation Task ==="

source /workspace/scripts/task_utils.sh

# Create necessary directories
PROJECT_DIR="/home/ga/AstroImages/classification"
OUTPUT_DIR="$PROJECT_DIR/output"
rm -rf "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy sample FITS file to the project directory
FITS_SOURCE="/opt/fits_samples/hst_wfpc2_sample.fits"
if [ ! -f "$FITS_SOURCE" ]; then
    echo "WARNING: Primary FITS source missing, falling back to UIT sample"
    FITS_SOURCE="/opt/fits_samples/uit_galaxy_sample.fits"
fi

cp "$FITS_SOURCE" "$PROJECT_DIR/deep_field.fits"
chown -R ga:ga "$PROJECT_DIR"

# Record timestamps and initial state for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Clear any previous run artifacts
rm -f /tmp/task_result.json 2>/dev/null || true

# Launch AstroImageJ
echo "Launching AstroImageJ..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start AIJ in the background
su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"

# Wait for AstroImageJ to fully launch
sleep 10
wait_for_window "ImageJ\|AstroImageJ\|AIJ" 30

# Maximize the window for better agent visibility
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial state screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="