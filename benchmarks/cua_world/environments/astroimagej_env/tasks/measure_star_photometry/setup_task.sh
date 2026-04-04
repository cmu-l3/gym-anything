#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Measure Star Photometry task ==="

# ============================================================
# CRITICAL: Setup should prepare the environment but NOT do the task
# The agent must:
# 1. Open the FITS file themselves
# 2. Perform aperture photometry
# 3. Record measurements
# ============================================================

# Record initial state (for detecting changes)
MEASUREMENT_DIR="/home/ga/AstroImages/measurements"
mkdir -p "$MEASUREMENT_DIR"
chown ga:ga "$MEASUREMENT_DIR"

# Count existing measurement files BEFORE task starts
INITIAL_COUNT=$(ls -1 "$MEASUREMENT_DIR"/*.txt "$MEASUREMENT_DIR"/*.csv "$MEASUREMENT_DIR"/*.tbl 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_measurement_count
echo "Initial measurement file count: $INITIAL_COUNT"

# Clear any previous state files that could be faked
rm -f /tmp/aij_state.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure FITS file exists in expected location
FITS_FILE="/home/ga/AstroImages/raw/hst_wfpc2_sample.fits"
if [ ! -f "$FITS_FILE" ]; then
    echo "Warning: FITS file not found at $FITS_FILE"
    # Try to copy from alternate location
    if [ -f "/opt/fits_samples/hst_wfpc2_sample.fits" ]; then
        cp /opt/fits_samples/hst_wfpc2_sample.fits "$FITS_FILE"
        chown ga:ga "$FITS_FILE"
        echo "Copied FITS file from /opt/fits_samples/"
    fi
fi

# List available FITS files for the agent
echo ""
echo "Available FITS files:"
ls -la /home/ga/AstroImages/raw/*.fits 2>/dev/null || echo "No FITS files found"

# ============================================================
# Launch AstroImageJ (but do NOT load any data!)
# The agent must open the FITS file themselves
# ============================================================

echo ""
echo "Launching AstroImageJ..."
launch_astroimagej 120

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

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Perform aperture photometry on a star"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Open the FITS file: ~/AstroImages/raw/hst_wfpc2_sample.fits"
echo "   (File > Open, or Ctrl+O)"
echo ""
echo "2. Use aperture photometry to measure a star's brightness"
echo "   (Analyze > Aperture Photometry > Multi-Aperture, or click on a star)"
echo ""
echo "3. The measurements will appear in a Results window"
echo ""
echo "FITS file location: $FITS_FILE"
echo "============================================================"
