#!/bin/bash
echo "=== Setting up Empirical SNR Map Generation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
WORK_DIR="/home/ga/AstroImages/snr_analysis"
OUT_DIR="$WORK_DIR/output"

rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

# Copy sample FITS file
SAMPLE_FILE="/opt/fits_samples/uit_galaxy_sample.fits"
if [ -f "$SAMPLE_FILE" ]; then
    cp "$SAMPLE_FILE" "$WORK_DIR/"
    echo "Copied uit_galaxy_sample.fits to working directory."
else
    echo "ERROR: Sample file not found at $SAMPLE_FILE"
    exit 1
fi

# Write instructions helper
cat > "$WORK_DIR/INSTRUCTIONS.txt" << 'EOF'
Goal: Create an SNR map and measure the area > 3.0 sigma.

1. Open uit_galaxy_sample.fits
2. Convert to 32-bit (Image > Type > 32-bit)
3. Measure blank sky background mean (mu) and stddev (sigma)
4. Use Process > Math to Subtract (mu) then Divide (sigma)
5. Save result to output/snr_map.fits
6. Apply threshold > 3.0 and measure area (pixels)
7. Record results in output/snr_results.txt formatted exactly as:
   background_mean: [val]
   background_stddev: [val]
   snr_greater_than_3_area: [val]
EOF

chown -R ga:ga "$WORK_DIR"

# Kill any existing AstroImageJ instances for a clean start
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize and focus the window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized and focused."
fi

# Wait a moment for UI to settle, then take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="