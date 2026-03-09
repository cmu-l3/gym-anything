#!/bin/bash
echo "=== Setting up Tumor Enhancement Pattern Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"

# Verify required files exist
T1_FILE="$SAMPLE_DIR/${SAMPLE_ID}_t1.nii.gz"
T1CE_FILE="$SAMPLE_DIR/${SAMPLE_ID}_t1ce.nii.gz"

if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce volume not found at $T1CE_FILE"
    exit 1
fi

if [ ! -f "$T1_FILE" ]; then
    echo "ERROR: T1 volume not found at $T1_FILE"
    exit 1
fi

echo "MRI volumes verified:"
echo "  T1: $T1_FILE"
echo "  T1ce: $T1CE_FILE"

# Pre-compute ground truth enhancement metrics
echo "Computing ground truth enhancement metrics..."
mkdir -p "$GROUND_TRUTH_DIR"

python3 << PYEOF
import os
import json
import sys

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
brats_dir = "$BRATS_DIR"
gt_dir = "$GROUND_TRUTH_DIR"
sample_dir = "$SAMPLE_DIR"

# Load images
t1_path = os.path.join(sample_dir, f"{sample_id}_t1.nii.gz")
t1ce_path = os.path.join(sample_dir, f"{sample_id}_t1ce.nii.gz")
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

print(f"Loading T1: {t1_path}")
print(f"Loading T1ce: {t1ce_path}")
print(f"Loading segmentation: {seg_path}")

t1_img = nib.load(t1_path)
t1ce_img = nib.load(t1ce_path)
seg_img = nib.load(seg_path)

t1_data = t1_img.get_fdata()
t1ce_data = t1ce_img.get_fdata()
seg_data = seg_img.get_fdata().astype(np.int32)

print(f"Volume shape: {t1_data.shape}")
print(f"Segmentation labels: {np.unique(seg_data)}")

# Get enhancing tumor region (BraTS label 4)
enhancing_mask = (seg_data == 4)
enhancing_voxels = np.sum(enhancing_mask)
print(f"Enhancing tumor voxels: {enhancing_voxels}")

if enhancing_voxels < 100:
    # If minimal enhancing tumor, use tumor core (labels 1 and 4)
    print("Minimal enhancing region, using tumor core instead")
    enhancing_mask = (seg_data == 1) | (seg_data == 4)
    enhancing_voxels = np.sum(enhancing_mask)

# Calculate tumor signal intensities
if enhancing_voxels > 0:
    t1_tumor_mean = float(np.mean(t1_data[enhancing_mask]))
    t1ce_tumor_mean = float(np.mean(t1ce_data[enhancing_mask]))
else:
    print("WARNING: No tumor region found")
    t1_tumor_mean = 1.0
    t1ce_tumor_mean = 1.0

# Find white matter reference (non-tumor, moderate-high T1 signal region)
non_tumor = (seg_data == 0)
t1_non_tumor = t1_data[non_tumor]
# Select voxels in upper quartile of intensity (likely white matter)
threshold = np.percentile(t1_non_tumor, 70)
wm_mask = non_tumor & (t1_data > threshold) & (t1_data < np.percentile(t1_non_tumor, 95))

if np.sum(wm_mask) > 1000:
    t1_wm_mean = float(np.mean(t1_data[wm_mask]))
    t1ce_wm_mean = float(np.mean(t1ce_data[wm_mask]))
else:
    # Fallback
    t1_wm_mean = float(np.percentile(t1_non_tumor, 75))
    t1ce_wm_mean = float(np.percentile(t1ce_data[non_tumor], 75))

print(f"T1 tumor mean: {t1_tumor_mean:.2f}")
print(f"T1ce tumor mean: {t1ce_tumor_mean:.2f}")
print(f"T1 WM mean: {t1_wm_mean:.2f}")
print(f"T1ce WM mean: {t1ce_wm_mean:.2f}")

# Calculate metrics
enhancement_ratio = t1ce_tumor_mean / t1_tumor_mean if t1_tumor_mean > 0 else 1.0
relative_enhancement = ((t1ce_tumor_mean - t1_tumor_mean) / t1_tumor_mean * 100) if t1_tumor_mean > 0 else 0
normalized_enhancement = ((t1ce_tumor_mean / t1ce_wm_mean) / (t1_tumor_mean / t1_wm_mean)) if (t1_tumor_mean > 0 and t1_wm_mean > 0 and t1ce_wm_mean > 0) else 1.0

print(f"Enhancement Ratio: {enhancement_ratio:.3f}")
print(f"Relative Enhancement: {relative_enhancement:.1f}%")

# Determine classification
if enhancement_ratio < 1.2 or relative_enhancement < 20:
    classification = "non-enhancing"
elif enhancement_ratio < 1.5 or relative_enhancement < 50:
    classification = "minimally-enhancing"
elif enhancement_ratio < 2.0 or relative_enhancement < 100:
    classification = "moderately-enhancing"
else:
    classification = "strongly-enhancing"

print(f"Classification: {classification}")

# Determine pattern (based on spatial distribution)
if enhancing_voxels > 500:
    t1ce_enhancing = t1ce_data[enhancing_mask]
    cv = np.std(t1ce_enhancing) / np.mean(t1ce_enhancing) if np.mean(t1ce_enhancing) > 0 else 0
    
    if cv > 0.4:
        pattern = "heterogeneous"
    else:
        pattern = "homogeneous"
    
    # Check for ring enhancement (higher signal at periphery)
    try:
        from scipy.ndimage import binary_erosion
        eroded = binary_erosion(enhancing_mask, iterations=2)
        peripheral = enhancing_mask & ~eroded
        if np.sum(peripheral) > 100 and np.sum(eroded) > 100:
            peripheral_mean = np.mean(t1ce_data[peripheral])
            core_mean = np.mean(t1ce_data[eroded])
            if peripheral_mean > core_mean * 1.3:
                pattern = "ring-enhancing"
    except:
        pass
else:
    pattern = "minimal"

print(f"Pattern: {pattern}")

# Find centroid of enhancing region for ROI validation
coords = np.argwhere(enhancing_mask)
if len(coords) > 0:
    centroid = coords.mean(axis=0).tolist()
    bbox_min = coords.min(axis=0).tolist()
    bbox_max = coords.max(axis=0).tolist()
else:
    centroid = [t1_data.shape[0]//2, t1_data.shape[1]//2, t1_data.shape[2]//2]
    bbox_min = [0, 0, 0]
    bbox_max = list(t1_data.shape)

# Save ground truth
gt_metrics = {
    "sample_id": sample_id,
    "t1_tumor_mean": round(t1_tumor_mean, 2),
    "t1ce_tumor_mean": round(t1ce_tumor_mean, 2),
    "t1_wm_mean": round(t1_wm_mean, 2),
    "t1ce_wm_mean": round(t1ce_wm_mean, 2),
    "enhancement_ratio": round(enhancement_ratio, 3),
    "relative_enhancement_percent": round(relative_enhancement, 1),
    "normalized_enhancement": round(normalized_enhancement, 3),
    "classification": classification,
    "pattern": pattern,
    "enhancing_tumor_voxels": int(enhancing_voxels),
    "enhancing_centroid_ijk": [round(c, 1) for c in centroid],
    "enhancing_bbox_min": [int(x) for x in bbox_min],
    "enhancing_bbox_max": [int(x) for x in bbox_max],
}

gt_path = os.path.join(gt_dir, f"{sample_id}_enhancement_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_metrics, f, indent=2)

print(f"\nGround truth saved: {gt_path}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_enhancement_gt.json" ]; then
    echo "ERROR: Failed to compute ground truth metrics"
    exit 1
fi
echo "Ground truth metrics computed"

# Record initial state - clean up any previous outputs
rm -f "$BRATS_DIR/enhancement_report.json" 2>/dev/null || true
rm -f "$BRATS_DIR/enhancement_rois.mrk.json" 2>/dev/null || true
rm -f /tmp/enhancement_task_result.json 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with T1ce image (primary image for enhancement assessment)
echo "Launching 3D Slicer with T1ce MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$T1CE_FILE" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/enhancement_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tumor Enhancement Pattern Characterization"
echo "================================================="
echo ""
echo "Sample ID: $SAMPLE_ID"
echo "T1ce (post-contrast) is loaded. You need to also load T1 (pre-contrast)."
echo ""
echo "T1 file location: $T1_FILE"
echo ""
echo "Your goals:"
echo "  1. Load the T1 sequence (Data module -> Add Data)"
echo "  2. Navigate to find the enhancing tumor region"
echo "  3. Place ROIs to measure signal intensities"
echo "  4. Calculate enhancement ratio and relative enhancement"
echo "  5. Classify the enhancement pattern"
echo "  6. Save report to: ~/Documents/SlicerData/BraTS/enhancement_report.json"
echo ""