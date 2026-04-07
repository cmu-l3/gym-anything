#!/bin/bash
echo "=== Setting up Clean Cosmic Rays task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and are clean
mkdir -p /home/ga/AstroImages/raw
mkdir -p /home/ga/AstroImages/processed
rm -f /home/ga/AstroImages/processed/* 2>/dev/null || true

# Ensure the raw sample file exists
RAW_IMAGE="/home/ga/AstroImages/raw/hst_wfpc2_sample.fits"
if [ ! -f "$RAW_IMAGE" ]; then
    echo "Copying sample image..."
    cp /opt/fits_samples/hst_wfpc2_sample.fits "$RAW_IMAGE" 2>/dev/null || true
fi

# Give ownership to the ga user
chown -R ga:ga /home/ga/AstroImages

# Verify raw image exists, otherwise fail setup gracefully
if [ ! -f "$RAW_IMAGE" ]; then
    echo "ERROR: Could not find raw image at $RAW_IMAGE"
    exit 1
fi

# Launch AstroImageJ
launch_astroimagej 60

# Focus and maximize window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot showing the clean starting state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="