#!/bin/bash
# Setup script for stain_deconvolution_quantification task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Stain Deconvolution Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RAW_DIR="$DATA_DIR/raw"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RAW_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous results
rm -f "$RESULTS_DIR/stain_separation_results.csv" 2>/dev/null || true
rm -f /tmp/stain_deconvolution_quantification_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ============================================================
# Prepare Real Data (from scikit-image)
# ============================================================
echo "Generating IHC tissue image..."
python3 << 'PYEOF'
import os
import sys
try:
    from skimage import data
    from PIL import Image
    import numpy as np

    # Load real immunohistochemistry image
    ihc = data.immunohistochemistry()
    
    # Save as TIFF (preferred format for Fiji)
    img = Image.fromarray(ihc)
    output_path = "/home/ga/ImageJ_Data/raw/ihc_tissue_sample.tif"
    img.save(output_path)
    print(f"Saved {output_path} ({img.size[0]}x{img.size[1]})")
    
    # Set permissions
    os.chmod(output_path, 0o666)

except Exception as e:
    print(f"Error preparing IHC data: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure file exists
if [ ! -f "$RAW_DIR/ihc_tissue_sample.tif" ]; then
    echo "ERROR: Failed to generate sample image"
    exit 1
fi
chown ga:ga "$RAW_DIR/ihc_tissue_sample.tif"

# ============================================================
# Create Macro to Open Image
# ============================================================
OPEN_MACRO="/tmp/open_ihc.ijm"
cat > "$OPEN_MACRO" << MACROEOF
open("$RAW_DIR/ihc_tissue_sample.tif");
run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
MACROEOF
chmod 644 "$OPEN_MACRO"
chown ga:ga "$OPEN_MACRO"

# ============================================================
# Launch Fiji
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

echo "Launching Fiji with IHC image..."
launch_fiji "$OPEN_MACRO"
FIJI_PID=$!

# Wait for Fiji window
wait_for_fiji 60
sleep 5

# Setup window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="