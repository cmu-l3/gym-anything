#!/bin/bash
echo "=== Setting up Stack Exposures & Measure SNR task ==="

source /workspace/scripts/task_utils.sh

# Create project directories
PROJECT_DIR="/home/ga/AstroImages/stacking_project"
FRAMES_DIR="$PROJECT_DIR/frames"
OUTPUT_DIR="$PROJECT_DIR/output"

rm -rf "$PROJECT_DIR"
mkdir -p "$FRAMES_DIR" "$OUTPUT_DIR"

# Extract WASP-12b data
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ -f "$WASP12_CACHE" ]; then
    echo "Extracting a subset of WASP-12b frames for stacking..."
    # Extract only the first 30 frames to save time and space
    tar -xzf "$WASP12_CACHE" -C /tmp --wildcards "WASP-12b/*_0[0-2][0-9].fits" 2>/dev/null || \
    tar -xzf "$WASP12_CACHE" -C /tmp 2>/dev/null
    
    # Move exactly 25 frames to the frames directory
    find /tmp/WASP-12b -name "*.fits" | sort | head -25 | xargs -I {} mv {} "$FRAMES_DIR/"
    rm -rf /tmp/WASP-12b
else
    echo "ERROR: Cached WASP-12b data not found at $WASP12_CACHE"
    exit 1
fi

# Verify frames were copied
FRAME_COUNT=$(ls -1 "$FRAMES_DIR"/*.fits 2>/dev/null | wc -l)
echo "Prepared $FRAME_COUNT frames in $FRAMES_DIR"

if [ "$FRAME_COUNT" -lt 10 ]; then
    echo "ERROR: Not enough frames extracted."
    exit 1
fi

# Compute ground truth and identify a target star using Python
echo "Computing ground truth and finding target star..."
python3 << 'PYEOF'
import os, json, glob
import numpy as np
from astropy.io import fits
from scipy import ndimage

FRAMES_DIR = "/home/ga/AstroImages/stacking_project/frames"
PROJECT_DIR = "/home/ga/AstroImages/stacking_project"

fits_files = sorted(glob.glob(os.path.join(FRAMES_DIR, "*.fits")))
if not fits_files:
    raise RuntimeError("No FITS files found for Python processing")

# Read frames into a stack (use first 25)
stack = []
for f in fits_files[:25]:
    data = fits.getdata(f).astype(float)
    stack.append(data)

stack = np.array(stack)
median_stack = np.median(stack, axis=0)

# Identify a bright star in the median stack
# Use a center crop to avoid edges
crop_size = 1000
cy, cx = median_stack.shape[0]//2, median_stack.shape[1]//2
center_crop = median_stack[cy-crop_size:cy+crop_size, cx-crop_size:cx+crop_size]

# Smooth and find peak
smoothed = ndimage.gaussian_filter(center_crop, sigma=3.0)
max_idx = np.argmax(smoothed)
peak_y, peak_x = np.unravel_index(max_idx, smoothed.shape)

# Convert back to full image coordinates
star_y = int(peak_y + cy - crop_size)
star_x = int(peak_x + cx - crop_size)

# Calculate sky background standard deviation in a blank region
sky_region_1 = stack[0, cy-500:cy-300, cx-500:cx-300]
sky_region_med = median_stack[cy-500:cy-300, cx-500:cx-300]

sky_std_single = float(np.std(sky_region_1))
sky_std_stacked = float(np.std(sky_region_med))

gt = {
    "num_frames": len(stack),
    "image_shape": list(median_stack.shape),
    "star_x": star_x,
    "star_y": star_y,
    "median_stack_mean": float(np.mean(median_stack)),
    "median_stack_std": float(np.std(median_stack)),
    "frame1_mean": float(np.mean(stack[0])),
    "sky_std_single": sky_std_single,
    "sky_std_stacked": sky_std_stacked,
    "theoretical_improvement": float(sky_std_single / sky_std_stacked) if sky_std_stacked > 0 else 5.0
}

with open("/tmp/stacking_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

# Write target info for the agent
with open(os.path.join(PROJECT_DIR, "target_info.txt"), "w") as f:
    f.write("Target Star Information for SNR Measurement\n")
    f.write("===========================================\n\n")
    f.write(f"Approximate X coordinate: {star_x}\n")
    f.write(f"Approximate Y coordinate: {star_y}\n\n")
    f.write("Please measure the SNR of this star in both a single frame and the stacked image.\n")

print(f"Target star identified at ({star_x}, {star_y})")
print(f"Theoretical SNR improvement: {gt['theoretical_improvement']:.2f}x")
PYEOF

chown -R ga:ga "$PROJECT_DIR"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Launch AstroImageJ (agent must load the sequence manually)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize the window for visibility
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot to document start state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="