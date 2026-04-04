#!/bin/bash
echo "=== Setting up WM/GM Contrast Assessment Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data
echo "Preparing BraTS T1-weighted MRI data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Run data preparation script
export GROUND_TRUTH_DIR BRATS_DIR
/workspace/scripts/prepare_brats_data.sh 2>&1 || {
    echo "WARNING: BraTS data preparation had issues"
}

# Get the sample ID used
SAMPLE_ID="BraTS2021_00000"
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi
echo "Using BraTS sample: $SAMPLE_ID"

# Determine the T1 file path
T1_FILE=""
for path in \
    "$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1.nii.gz" \
    "$BRATS_DIR/${SAMPLE_ID}_t1.nii.gz" \
    "$BRATS_DIR/$SAMPLE_ID/t1.nii.gz"; do
    if [ -f "$path" ]; then
        T1_FILE="$path"
        break
    fi
done

if [ -z "$T1_FILE" ]; then
    echo "ERROR: T1 file not found!"
    ls -la "$BRATS_DIR/" 2>/dev/null || true
    ls -la "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || true
    exit 1
fi
echo "T1 file found: $T1_FILE"

# Record initial state
rm -f /tmp/wm_gm_task_result.json 2>/dev/null || true
rm -f "$EXPORTS_DIR/wm_gm_contrast.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$SAMPLE_ID" > /tmp/wm_gm_sample_id.txt

# Compute reference WM/GM values from the T1 data for verification
echo "Computing reference intensity statistics..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

t1_path = "$T1_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

print(f"Loading T1 volume from {t1_path}...")
t1_nii = nib.load(t1_path)
t1_data = t1_nii.get_fdata()
print(f"T1 shape: {t1_data.shape}")

# Compute basic statistics
brain_mask = t1_data > np.percentile(t1_data[t1_data > 0], 10)
brain_voxels = t1_data[brain_mask]

# Estimate WM and GM regions using intensity histogram
# For T1: WM is brighter (higher percentiles), GM is intermediate
# Typical approach: WM ~ 80th percentile, GM ~ 50th percentile

percentiles = np.percentile(brain_voxels, [25, 50, 75, 90, 95])
print(f"Brain intensity percentiles (25,50,75,90,95): {percentiles}")

# Estimate GM as ~40-60th percentile, WM as ~75-90th percentile
gm_intensity_estimate = np.percentile(brain_voxels, 50)
wm_intensity_estimate = np.percentile(brain_voxels, 85)

# The ratio for T1
estimated_ratio = wm_intensity_estimate / gm_intensity_estimate if gm_intensity_estimate > 0 else 0

print(f"Estimated GM intensity: {gm_intensity_estimate:.1f}")
print(f"Estimated WM intensity: {wm_intensity_estimate:.1f}")
print(f"Estimated WM/GM ratio: {estimated_ratio:.3f}")

# Find good sample locations for WM and GM
# WM: central brain region with high intensity
# GM: outer cortical region with intermediate intensity

shape = t1_data.shape
mid_z = shape[2] // 2  # Mid-axial slice
mid_y = shape[1] // 2
mid_x = shape[0] // 2

# Sample central region for WM (centrum semiovale region)
wm_region = t1_data[mid_x-10:mid_x+10, mid_y-10:mid_y+10, mid_z-5:mid_z+5]
wm_sample_intensity = np.percentile(wm_region[wm_region > wm_intensity_estimate * 0.8], 50) if np.any(wm_region > wm_intensity_estimate * 0.8) else wm_intensity_estimate

# Sample outer region for GM (cortex)
# Look at the outer shell of brain tissue
outer_mask = brain_mask.copy()
from scipy.ndimage import binary_erosion
inner_mask = binary_erosion(brain_mask, iterations=15)
cortex_mask = outer_mask & ~inner_mask
gm_voxels = t1_data[cortex_mask]
gm_sample_intensity = np.percentile(gm_voxels, 50) if len(gm_voxels) > 0 else gm_intensity_estimate

# Save reference data
ref_data = {
    "sample_id": sample_id,
    "t1_path": t1_path,
    "volume_shape": list(t1_data.shape),
    "intensity_min": float(np.min(t1_data)),
    "intensity_max": float(np.max(t1_data)),
    "brain_intensity_percentiles": {
        "p25": float(percentiles[0]),
        "p50": float(percentiles[1]),
        "p75": float(percentiles[2]),
        "p90": float(percentiles[3]),
        "p95": float(percentiles[4])
    },
    "estimated_gm_intensity": float(gm_intensity_estimate),
    "estimated_wm_intensity": float(wm_intensity_estimate),
    "estimated_wm_gm_ratio": float(estimated_ratio),
    "gm_sample_reference": float(gm_sample_intensity),
    "wm_sample_reference": float(wm_sample_intensity),
    "reference_ratio": float(wm_sample_intensity / gm_sample_intensity) if gm_sample_intensity > 0 else 0,
    "acceptable_ratio_range": {"min": 1.0, "max": 2.0},
    "good_contrast_range": {"min": 1.1, "max": 1.5}
}

ref_path = os.path.join(gt_dir, f"{sample_id}_wm_gm_reference.json")
with open(ref_path, "w") as f:
    json.dump(ref_data, f, indent=2)

print(f"Reference data saved to {ref_path}")
print(f"Reference WM/GM ratio: {ref_data['reference_ratio']:.3f}")
PYEOF

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Launch 3D Slicer with the T1 volume
echo "Launching 3D Slicer with T1 volume..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the T1 file
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$T1_FILE' > /tmp/slicer_wm_gm.log 2>&1" &

echo "Waiting for Slicer to start and load data..."
wait_for_slicer 90

# Navigate to a mid-brain slice (good for seeing WM/GM)
echo "Setting up optimal view for WM/GM assessment..."
sleep 5

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/wm_gm_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "T1 volume: $T1_FILE"
echo "Output file: $EXPORTS_DIR/wm_gm_contrast.json"
echo ""
echo "INSTRUCTIONS:"
echo "1. Navigate to an axial slice showing both white matter and gray matter"
echo "2. Place a fiducial in WHITE MATTER (bright central brain tissue)"
echo "3. Place a fiducial in GRAY MATTER (darker cortical tissue)"
echo "4. Record the intensity values and calculate WM/GM ratio"
echo "5. Save results to: ~/Documents/SlicerData/Exports/wm_gm_contrast.json"
echo ""
echo "Expected WM/GM ratio for good T1 contrast: 1.1 to 1.5"