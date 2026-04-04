#!/bin/bash
echo "=== Setting up Liver-to-Spleen Ratio Measurement Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clear previous results
rm -f /tmp/ls_ratio_task_result.json 2>/dev/null || true
rm -f "$EXPORTS_DIR/ls_ratio_result.json" 2>/dev/null || true

# Prepare AMOS abdominal CT data
echo "Preparing AMOS abdominal CT data..."
export AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "amos_0001"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

echo "Using AMOS case: $CASE_ID"

# Verify data files exist
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    exit 1
fi
echo "CT file found: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

# Record initial state - no output file should exist
echo "0" > /tmp/initial_output_exists.txt
if [ -f "$EXPORTS_DIR/ls_ratio_result.json" ]; then
    echo "1" > /tmp/initial_output_exists.txt
    stat -c %Y "$EXPORTS_DIR/ls_ratio_result.json" > /tmp/initial_output_mtime.txt
fi

# Create reference ground truth for expected measurements
# Based on the synthetic/real AMOS data properties
echo "Creating reference data for verification..."
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

case_id = "$CASE_ID"
amos_dir = "$AMOS_DIR"
gt_dir = "$GROUND_TRUTH_DIR"

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

print(f"Loading CT from {ct_path}")
ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata()
spacing = ct_nii.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# Try to load label map for liver/spleen regions
liver_hu_samples = []
spleen_hu_samples = []

if os.path.exists(label_path):
    print(f"Loading labels from {label_path}")
    label_nii = nib.load(label_path)
    label_data = label_nii.get_fdata().astype(int)
    
    # AMOS labels: 6=liver, 1=spleen
    liver_mask = (label_data == 6)
    spleen_mask = (label_data == 1)
    
    if np.any(liver_mask):
        liver_hu_samples = ct_data[liver_mask].flatten()
        print(f"Liver voxels: {len(liver_hu_samples)}")
    
    if np.any(spleen_mask):
        spleen_hu_samples = ct_data[spleen_mask].flatten()
        print(f"Spleen voxels: {len(spleen_hu_samples)}")

# Calculate reference values
ref_data = {
    "case_id": case_id,
    "ct_shape": list(ct_data.shape),
    "spacing_mm": [float(s) for s in spacing],
}

if len(liver_hu_samples) > 100:
    ref_data["liver_hu_mean"] = float(np.mean(liver_hu_samples))
    ref_data["liver_hu_std"] = float(np.std(liver_hu_samples))
    ref_data["liver_hu_median"] = float(np.median(liver_hu_samples))
else:
    # Fallback for synthetic data
    ref_data["liver_hu_mean"] = 60.0
    ref_data["liver_hu_std"] = 15.0
    ref_data["liver_hu_median"] = 60.0

if len(spleen_hu_samples) > 100:
    ref_data["spleen_hu_mean"] = float(np.mean(spleen_hu_samples))
    ref_data["spleen_hu_std"] = float(np.std(spleen_hu_samples))
    ref_data["spleen_hu_median"] = float(np.median(spleen_hu_samples))
else:
    # Fallback for synthetic data
    ref_data["spleen_hu_mean"] = 55.0
    ref_data["spleen_hu_std"] = 12.0
    ref_data["spleen_hu_median"] = 55.0

# Calculate expected L/S ratio
if ref_data["spleen_hu_mean"] > 0:
    ref_data["expected_ls_ratio"] = ref_data["liver_hu_mean"] / ref_data["spleen_hu_mean"]
else:
    ref_data["expected_ls_ratio"] = 1.0

# Determine expected classification
ls_ratio = ref_data["expected_ls_ratio"]
if ls_ratio >= 1.0:
    ref_data["expected_classification"] = "Normal"
elif ls_ratio >= 0.8:
    ref_data["expected_classification"] = "Borderline"
else:
    ref_data["expected_classification"] = "Abnormal"

# Find recommended slice for measurement
# Look for slice with both liver and spleen visible
best_slice = ct_data.shape[2] // 2
if os.path.exists(label_path):
    both_visible = np.zeros(ct_data.shape[2])
    for z in range(ct_data.shape[2]):
        liver_slice = np.sum(label_data[:, :, z] == 6)
        spleen_slice = np.sum(label_data[:, :, z] == 1)
        if liver_slice > 100 and spleen_slice > 100:
            both_visible[z] = min(liver_slice, spleen_slice)
    
    if np.any(both_visible > 0):
        best_slice = int(np.argmax(both_visible))

ref_data["recommended_slice"] = best_slice

# Save reference data
ref_path = os.path.join(gt_dir, f"{case_id}_ls_reference.json")
with open(ref_path, "w") as f:
    json.dump(ref_data, f, indent=2)

print(f"\nReference data saved to {ref_path}")
print(f"Expected liver HU: {ref_data['liver_hu_mean']:.1f} ± {ref_data['liver_hu_std']:.1f}")
print(f"Expected spleen HU: {ref_data['spleen_hu_mean']:.1f} ± {ref_data['spleen_hu_std']:.1f}")
print(f"Expected L/S ratio: {ref_data['expected_ls_ratio']:.3f}")
print(f"Expected classification: {ref_data['expected_classification']}")
print(f"Recommended slice: {ref_data['recommended_slice']}")
PYEOF

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$EXPORTS_DIR" 2>/dev/null || true

# Kill any existing Slicer instance
echo "Preparing 3D Slicer..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the CT data loaded
echo "Launching 3D Slicer with AMOS CT data..."
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$CT_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start and load data..."
sleep 10

# Wait for Slicer window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to load
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/ls_ratio_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Calculate Liver-to-Spleen Ratio for Steatosis Assessment"
echo ""
echo "CT data loaded: $CT_FILE"
echo "Output file required: $EXPORTS_DIR/ls_ratio_result.json"
echo ""
echo "INSTRUCTIONS:"
echo "1. Navigate to a slice showing both liver (right) and spleen (left)"
echo "2. Create ROI in liver parenchyma, measure mean HU"
echo "3. Create ROI in spleen parenchyma, measure mean HU"
echo "4. Calculate L/S ratio and save results to the output JSON file"
echo ""