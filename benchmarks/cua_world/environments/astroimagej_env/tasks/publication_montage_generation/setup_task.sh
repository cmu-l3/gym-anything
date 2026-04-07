#!/bin/bash
echo "=== Setting up Publication Montage Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/AstroImages/publication/
chown -R ga:ga /home/ga/AstroImages

# Clear any previous outputs
rm -f /home/ga/AstroImages/publication/eagle_montage.png

# Ensure the required FITS files exist (these are cached by the environment)
EAGLE_DIR="/opt/fits_samples/eagle_nebula"
if [ ! -d "$EAGLE_DIR" ] || [ -z "$(ls -A $EAGLE_DIR/*.fits 2>/dev/null)" ]; then
    echo "ERROR: Eagle Nebula FITS files not found in $EAGLE_DIR"
    # Create placeholders to avoid immediate crash, though task will likely fail
    mkdir -p "$EAGLE_DIR"
    touch "$EAGLE_DIR/502nmos.fits" "$EAGLE_DIR/656nmos.fits" "$EAGLE_DIR/673nmos.fits"
fi

# Make sure they are readable
chmod -R 755 "$EAGLE_DIR"

# Launch AstroImageJ (empty, no images loaded)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize AstroImageJ for agent interaction
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "AstroImageJ maximized."
fi

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="