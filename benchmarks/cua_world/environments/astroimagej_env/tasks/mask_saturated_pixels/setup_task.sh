#!/bin/bash
echo "=== Setting up Mask Saturated Pixels Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Create directories
RAW_DIR="/home/ga/AstroImages/quality_control"
PROC_DIR="/home/ga/AstroImages/processed"
rm -rf "$RAW_DIR" "$PROC_DIR" 2>/dev/null || true
mkdir -p "$RAW_DIR" "$PROC_DIR"

# Provide a raw science image containing saturated pixels.
# We extract a real frame from the WASP-12b dataset cached during installation.
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"
TARGET_FILE="$RAW_DIR/science_raw.fits"

echo "Extracting raw science frame..."
if [ -f "$WASP12_CACHE" ]; then
    # Extract just one fits file to serve as the target
    mkdir -p /tmp/wasp12b_extract
    tar -xzf "$WASP12_CACHE" -C /tmp/wasp12b_extract 2>/dev/null || true
    
    # Find the first FITS file and move it
    FIRST_FITS=$(find /tmp/wasp12b_extract -name "*.fits" -o -name "*.fit" | head -n 1)
    if [ -n "$FIRST_FITS" ]; then
        mv "$FIRST_FITS" "$TARGET_FILE"
        echo "Successfully extracted WASP-12b frame: $TARGET_FILE"
    fi
    rm -rf /tmp/wasp12b_extract
fi

# Fallback if WASP-12b cache is missing or extraction failed
if [ ! -f "$TARGET_FILE" ]; then
    echo "Fallback: using HST WFPC2 sample..."
    cp /opt/fits_samples/hst_wfpc2_sample.fits "$TARGET_FILE" 2>/dev/null || \
    cp /opt/fits_samples/eagle_nebula/656nmos.fits "$TARGET_FILE" 2>/dev/null
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "ERROR: Failed to provide a source FITS file!"
    exit 1
fi

chown -R ga:ga /home/ga/AstroImages

# Launch AstroImageJ so the agent is ready to start
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true

AIJ_PATH=""
for path in \
    "/usr/local/bin/aij" \
    "/opt/astroimagej/astroimagej/bin/AstroImageJ" \
    "/opt/astroimagej/AstroImageJ/bin/AstroImageJ"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

if [ -n "$AIJ_PATH" ]; then
    export DISPLAY=:1
    xhost +local: 2>/dev/null || true
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx2g' '$AIJ_PATH' > /tmp/astroimagej_ga.log 2>&1" &
    
    # Wait for AstroImageJ to start
    sleep 8
    
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    fi
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="