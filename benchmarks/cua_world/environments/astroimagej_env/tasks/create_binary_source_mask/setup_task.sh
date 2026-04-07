#!/bin/bash
echo "=== Setting up create_binary_source_mask task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create directories and prepare files
MASKING_DIR="/home/ga/AstroImages/masking"
mkdir -p "$MASKING_DIR"

# Copy the original file
if [ -f "/opt/fits_samples/hst_wfpc2_sample.fits" ]; then
    cp /opt/fits_samples/hst_wfpc2_sample.fits "$MASKING_DIR/"
else
    echo "Warning: Sample file missing from /opt/fits_samples/"
fi
chown -R ga:ga "$MASKING_DIR"

# Clean up any pre-existing output files and state
rm -f "$MASKING_DIR/source_mask.fits" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize the AstroImageJ window for better agent interaction
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized"
fi

# Take initial screenshot to record starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="