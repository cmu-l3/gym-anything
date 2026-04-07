#!/bin/bash
echo "=== Setting up Temporal Binning Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
RAW_DIR="/home/ga/AstroImages/time_series/raw"
BINNED_DIR="/home/ga/AstroImages/time_series/binned"
rm -rf "/home/ga/AstroImages/time_series"
mkdir -p "$RAW_DIR" "$BINNED_DIR"

# Extract real WASP-12b data from cached tarball
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: WASP-12b data not found at $WASP12_CACHE"
    # Fallback to download if cache is missing
    echo "Downloading from University of Louisville..."
    wget -q --show-progress "https://www.astro.louisville.edu/software/astroimagej/examples/WASP-12b_example_calibrated_images.tar.gz" -O /tmp/wasp12.tar.gz
    WASP12_CACHE="/tmp/wasp12.tar.gz"
fi

echo "Extracting WASP-12b calibrated images..."
tar -xzf "$WASP12_CACHE" -C /tmp
# Images are usually inside a WASP-12b folder inside the tar
mv /tmp/WASP-12b/*.fits "$RAW_DIR/" 2>/dev/null || mv /tmp/*.fits "$RAW_DIR/" 2>/dev/null

rm -rf /tmp/WASP-12b /tmp/wasp12.tar.gz 2>/dev/null || true

# Compute Ground Truth dynamically from the real data
echo "Computing ground truth from real data..."
cat > /tmp/compute_gt.py << 'EOF'
import glob
import json
import os
import numpy as np
try:
    from astropy.io import fits
    ASTROPY_AVAILABLE = True
except ImportError:
    ASTROPY_AVAILABLE = False

RAW_DIR = "/home/ga/AstroImages/time_series/raw"
files = sorted(glob.glob(os.path.join(RAW_DIR, "*.fits")))

gt = {
    "success": False,
    "num_raw_frames": len(files)
}

if ASTROPY_AVAILABLE and len(files) >= 10:
    try:
        # Load first 10 frames for the median projection
        data_stack = []
        for f in files[:10]:
            data_stack.append(fits.getdata(f).astype(np.float32))
        
        data_stack = np.array(data_stack)
        raw_slice_1 = data_stack[0]
        binned_slice_1 = np.median(data_stack, axis=0)
        
        # ROI: X=200, Y=200, W=400, H=400 (Note: numpy arrays are indexed [Y, X])
        roi_raw = raw_slice_1[200:600, 200:600]
        roi_binned = binned_slice_1[200:600, 200:600]
        
        # ImageJ standard deviation uses sample stddev (ddof=1)
        raw_std = float(np.std(roi_raw, ddof=1))
        binned_std = float(np.std(roi_binned, ddof=1))
        
        gt["success"] = True
        gt["expected_binned_frames"] = len(files) // 10
        gt["raw_std"] = raw_std
        gt["binned_std"] = binned_std
        gt["reduction_factor"] = raw_std / binned_std if binned_std > 0 else 0
        
        print(f"GT Raw StdDev: {raw_std:.4f}")
        print(f"GT Binned StdDev: {binned_std:.4f}")
        print(f"GT Expected Frames: {gt['expected_binned_frames']}")
        
    except Exception as e:
        gt["error"] = str(e)
        print(f"Error computing GT: {e}")

with open("/tmp/ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)
EOF

python3 /tmp/compute_gt.py

chown -R ga:ga "/home/ga/AstroImages"

# Start AstroImageJ cleanly
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' /usr/local/bin/aij > /tmp/aij.log 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        echo "AstroImageJ window found: $WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="