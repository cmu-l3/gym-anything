#!/bin/bash
echo "=== Setting up galaxy_unsharp_masking task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure target directories exist
mkdir -p /home/ga/AstroImages/processed
chown ga:ga /home/ga/AstroImages/processed

# Ensure source file is ready
SOURCE_FILE="/home/ga/AstroImages/raw/uit_galaxy_sample.fits"
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Warning: Source file missing, attempting to restore from opt..."
    cp /opt/fits_samples/uit_galaxy_sample.fits "$SOURCE_FILE" 2>/dev/null || true
fi

# Clean up any pre-existing output to prevent false positives
OUTPUT_FILE="/home/ga/AstroImages/processed/galaxy_highpass.fits"
rm -f "$OUTPUT_FILE" 2>/dev/null

# Start AstroImageJ cleanly
pkill -f "AstroImageJ|aij" 2>/dev/null || true
sleep 2

echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize the main AstroImageJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_horz 2>/dev/null || true
fi

# Give UI time to stabilize
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="