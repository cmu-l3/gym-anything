#!/bin/bash
echo "=== Setting up Synthesize Two-Band RGB Composite Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/AstroImages/outreach"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Source FITS from cached install data
M12_DIR="/opt/fits_samples/m12"

echo "Copying real M12 VLT observations..."
if [ -f "$M12_DIR/Bcomb.fits" ] && [ -f "$M12_DIR/Vcomb.fits" ]; then
    cp "$M12_DIR/Bcomb.fits" "$PROJECT_DIR/"
    cp "$M12_DIR/Vcomb.fits" "$PROJECT_DIR/"
else
    echo "ERROR: Required M12 FITS files not found in cache. Extracting from zips if available..."
    if [ -f "$M12_DIR/Bcomb.zip" ] && [ -f "$M12_DIR/Vcomb.zip" ]; then
        unzip -q "$M12_DIR/Bcomb.zip" -d "$PROJECT_DIR/"
        unzip -q "$M12_DIR/Vcomb.zip" -d "$PROJECT_DIR/"
    else
        echo "CRITICAL ERROR: No M12 data available."
        exit 1
    fi
fi

# Ensure proper ownership
chown -R ga:ga "$PROJECT_DIR"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize the AstroImageJ window for the agent
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized"
fi

# Take initial screenshot to document start state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo "M12 FITS files are ready in ~/AstroImages/outreach/"