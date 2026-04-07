#!/bin/bash
echo "=== Setting up Eagle ROI Transfer Task ==="
source /workspace/scripts/task_utils.sh

# Prepare directories
WORK_DIR="/home/ga/AstroImages/excitation_project"
OUT_DIR="/home/ga/AstroImages/measurements"
rm -rf "$WORK_DIR" "$OUT_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"

# Copy real Hubble Space Telescope images of Eagle Nebula
cp /opt/fits_samples/eagle_nebula/656nmos.fits "$WORK_DIR/"
cp /opt/fits_samples/eagle_nebula/502nmos.fits "$WORK_DIR/"
chown -R ga:ga /home/ga/AstroImages

# Clean up any old state
rm -f /tmp/task_result.json

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_time

# Start AstroImageJ and wait for it
launch_astroimagej 60

# Maximize it for the agent
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Capture initial state
take_screenshot /tmp/task_start.png

echo "Setup complete"