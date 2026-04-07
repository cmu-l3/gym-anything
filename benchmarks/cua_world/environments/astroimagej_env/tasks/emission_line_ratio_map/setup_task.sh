#!/bin/bash
echo "=== Setting up Emission Line Ratio Map task ==="

source /workspace/scripts/task_utils.sh

# Define directories
RAW_DIR="/home/ga/AstroImages/raw/eagle_nebula"
PROC_DIR="/home/ga/AstroImages/processed"

# Create directories
sudo -u ga mkdir -p "$RAW_DIR"
sudo -u ga mkdir -p "$PROC_DIR"

# Clean any existing output files from previous runs
sudo -u ga rm -f "$PROC_DIR/sii_halpha_ratio.fits" 2>/dev/null || true
sudo -u ga rm -f "$PROC_DIR/sii_halpha_ratio.png" 2>/dev/null || true

# Ensure real Eagle Nebula HST data is present
if [ ! -f "$RAW_DIR/673nmos.fits" ] || [ ! -f "$RAW_DIR/656nmos.fits" ]; then
    echo "Copying Eagle Nebula samples to working directory..."
    cp /opt/fits_samples/eagle_nebula/673nmos.fits "$RAW_DIR/" 2>/dev/null || true
    cp /opt/fits_samples/eagle_nebula/656nmos.fits "$RAW_DIR/" 2>/dev/null || true
    chown -R ga:ga "$RAW_DIR"
fi

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Launch AstroImageJ
launch_astroimagej 60

# Maximize and focus the window to ensure agent visibility
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot to prove starting state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="