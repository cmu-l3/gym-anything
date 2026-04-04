#!/bin/bash
set -e
echo "=== Setting up Contrast Enhancement Subtraction Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create required directories
mkdir -p /home/ga/Documents/SlicerData/Exports
mkdir -p /home/ga/Documents/SlicerData/BraTS
mkdir -p /var/lib/slicer/ground_truth
chown -R ga:ga /home/ga/Documents/SlicerData

# Clean up any previous task artifacts
rm -f /home/ga/Documents/SlicerData/Exports/enhancement_map.nii.gz 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/subtraction_task_result.json 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_export_count.txt
ls -1 /home/ga/Documents/SlicerData/Exports/*.nii.gz 2>/dev/null | wc -l > /tmp/initial_export_count.txt || echo "0" > /tmp/initial_export_count.txt

# Prepare BraTS data (downloads if needed)
echo "Preparing BraTS brain tumor data..."
bash /workspace/scripts/prepare_brats_data.sh 2>&1 || {
    echo "WARNING: BraTS data preparation had issues, continuing..."
}

# Verify BraTS data was prepared and get sample ID
SAMPLE_ID=$(cat /tmp/brats_sample_id 2>/dev/null || echo "BraTS2021_00000")
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"

# Find the case directory
CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
if [ ! -d "$CASE_DIR" ]; then
    CASE_DIR="$BRATS_DIR"
fi

# Verify required files exist
T1_FILE="$CASE_DIR/${SAMPLE_ID}_t1.nii.gz"
T1CE_FILE="$CASE_DIR/${SAMPLE_ID}_t1ce.nii.gz"

echo "Looking for T1 at: $T1_FILE"
echo "Looking for T1ce at: $T1CE_FILE"

if [ ! -f "$T1_FILE" ]; then
    echo "ERROR: T1 file not found at $T1_FILE"
    echo "Contents of BRATS_DIR:"
    ls -la "$BRATS_DIR/" 2>/dev/null || echo "Directory not found"
    echo "Contents of CASE_DIR:"
    ls -la "$CASE_DIR/" 2>/dev/null || echo "Directory not found"
    exit 1
fi

if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    ls -la "$CASE_DIR/" 2>/dev/null || true
    exit 1
fi

echo "Found T1: $T1_FILE ($(du -h "$T1_FILE" | cut -f1))"
echo "Found T1ce: $T1CE_FILE ($(du -h "$T1CE_FILE" | cut -f1))"

# Pre-compute expected enhancement statistics for verification
echo "Computing ground truth enhancement statistics..."
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

sample_id = "$SAMPLE_ID"
case_dir = "$CASE_DIR"
gt_dir = "/var/lib/slicer/ground_truth"

t1_path = os.path.join(case_dir, f"{sample_id}_t1.nii.gz")
t1ce_path = os.path.join(case_dir, f"{sample_id}_t1ce.nii.gz")
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

print(f"Loading T1 from: {t1_path}")
print(f"Loading T1ce from: {t1ce_path}")

# Load volumes
t1_nii = nib.load(t1_path)
t1 = t1_nii.get_fdata().astype(np.float32)
t1ce = nib.load(t1ce_path).get_fdata().astype(np.float32)

# Compute expected subtraction
expected_sub = t1ce - t1

# Get volume info
enhancement_stats = {
    "sample_id": sample_id,
    "input_shape": list(t1.shape),
    "t1_mean": float(np.mean(t1[t1 > 0])) if np.any(t1 > 0) else 0,
    "t1ce_mean": float(np.mean(t1ce[t1ce > 0])) if np.any(t1ce > 0) else 0,
    "expected_sub_mean": float(np.mean(expected_sub[t1 > 0])) if np.any(t1 > 0) else 0,
    "expected_sub_std": float(np.std(expected_sub[t1 > 0])) if np.any(t1 > 0) else 0,
    "expected_sub_max": float(np.max(expected_sub)),
    "expected_sub_min": float(np.min(expected_sub)),
}

# Load segmentation if available for enhancement region analysis
if os.path.exists(seg_path):
    seg = nib.load(seg_path).get_fdata().astype(np.int32)
    # BraTS labels: 1=necrotic, 2=edema, 4=enhancing tumor
    enhancing_mask = (seg == 4)
    non_tumor_mask = (seg == 0) & (t1 > 0)
    
    if np.any(enhancing_mask):
        enhancement_stats["enhancing_region_mean"] = float(np.mean(expected_sub[enhancing_mask]))
        enhancement_stats["enhancing_region_count"] = int(np.sum(enhancing_mask))
    
    if np.any(non_tumor_mask):
        enhancement_stats["non_tumor_mean"] = float(np.mean(expected_sub[non_tumor_mask]))
        
    if np.any(enhancing_mask) and np.any(non_tumor_mask):
        non_tumor_val = np.mean(expected_sub[non_tumor_mask])
        enhancing_val = np.mean(expected_sub[enhancing_mask])
        if abs(non_tumor_val) > 1e-6:
            ratio = enhancing_val / (abs(non_tumor_val) + 1e-6)
            enhancement_stats["enhancement_ratio"] = float(ratio)
        else:
            enhancement_stats["enhancement_ratio"] = float(enhancing_val) if enhancing_val > 0 else 0.0
    
    print(f"Enhancing tumor voxels: {enhancement_stats.get('enhancing_region_count', 0)}")
else:
    print("Warning: Ground truth segmentation not found")

# Save for verification
stats_path = os.path.join(gt_dir, f"{sample_id}_enhancement_stats.json")
os.makedirs(gt_dir, exist_ok=True)
with open(stats_path, 'w') as f:
    json.dump(enhancement_stats, f, indent=2)

print(f"Enhancement statistics saved to {stats_path}")
print(f"Expected enhancement in tumor region: {enhancement_stats.get('enhancing_region_mean', 'N/A')}")
print(f"Expected enhancement ratio: {enhancement_stats.get('enhancement_ratio', 'N/A')}")
PYEOF

# Set permissions on ground truth
chmod 700 /var/lib/slicer/ground_truth 2>/dev/null || true
chown -R root:root /var/lib/slicer/ground_truth 2>/dev/null || true

# Store paths for agent reference
echo "$SAMPLE_ID" > /tmp/current_sample_id
echo "$CASE_DIR" > /tmp/current_case_dir

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Start 3D Slicer
echo "Starting 3D Slicer..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!
echo "Slicer PID: $SLICER_PID"

# Wait for Slicer window
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for full module loading
echo "Waiting for Slicer modules to load..."
sleep 15

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Take initial screenshot
mkdir -p /tmp/task_screenshots
DISPLAY=:1 scrot /tmp/task_screenshots/initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "T1 file: $T1_FILE"
echo "T1ce file: $T1CE_FILE"
echo "Output should be saved to: ~/Documents/SlicerData/Exports/enhancement_map.nii.gz"
echo ""
echo "3D Slicer is ready for the enhancement subtraction task."