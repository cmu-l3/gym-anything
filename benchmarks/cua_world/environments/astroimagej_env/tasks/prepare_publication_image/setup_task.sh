#!/bin/bash
echo "=== Setting up Prepare Publication Image Task ==="

source /workspace/scripts/task_utils.sh

# Set up working directories
PROJECT_DIR="/home/ga/AstroImages/publication"
OUTPUT_DIR="$PROJECT_DIR/output"
rm -rf "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

# Provide the real HST Eagle Nebula H-alpha FITS file
SOURCE_FITS="/opt/fits_samples/eagle_nebula/656nmos.fits"
TARGET_FITS="$PROJECT_DIR/eagle_halpha.fits"

if [ -f "$SOURCE_FITS" ]; then
    cp "$SOURCE_FITS" "$TARGET_FITS"
    echo "Copied real HST Eagle Nebula FITS to working directory."
else
    echo "ERROR: Source FITS $SOURCE_FITS not found! Ensure environment is installed correctly."
    exit 1
fi

chown -R ga:ga "$PROJECT_DIR"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_output_count

# Kill any existing AstroImageJ instances for a clean start
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize AstroImageJ for the agent
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized."
fi

# Capture initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task Setup Complete ==="
echo "AstroImageJ is running. The agent should open the FITS file, process it, and export the PNG."