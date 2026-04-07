#!/bin/bash
echo "=== Setting up Inverted Finding Chart Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time

# Create necessary directories
RAW_DIR="/home/ga/AstroImages/finding_charts/raw"
OUT_DIR="/home/ga/AstroImages/finding_charts/output"
mkdir -p "$RAW_DIR" "$OUT_DIR"

# Clean up any prior attempts
rm -f "$OUT_DIR"/* 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Provide the Eagle Nebula FITS file
if [ -f "/opt/fits_samples/eagle_nebula/656nmos.fits" ]; then
    cp "/opt/fits_samples/eagle_nebula/656nmos.fits" "$RAW_DIR/"
else
    echo "ERROR: Required FITS file missing from environment!"
    exit 1
fi

# Create instructions file on Desktop for reference
cat > /home/ga/Desktop/chart_instructions.txt << 'EOF'
TARGET: Eagle Nebula (M16) Core Finding Chart

1. Open File: ~/AstroImages/finding_charts/raw/656nmos.fits
2. Crop Image: Width=500, Height=500, X=550, Y=550
3. Adjust Contrast: Enhance visibility of the nebula's pillars
4. Invert Image: Black stars/nebula on a white background
5. Add Marker: Point to/circle the tip of the largest pillar
6. Add Text: "M16 Core"
7. Flatten: Burn the overlay into the image
8. Export: Save as PNG to ~/AstroImages/finding_charts/output/m16_finding_chart.png
EOF

# Fix permissions
chown -R ga:ga /home/ga/AstroImages/finding_charts
chown ga:ga /home/ga/Desktop/chart_instructions.txt

# Launch AstroImageJ and maximize it
echo "Launching AstroImageJ..."
launch_astroimagej 60

WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Allow UI to stabilize and take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="