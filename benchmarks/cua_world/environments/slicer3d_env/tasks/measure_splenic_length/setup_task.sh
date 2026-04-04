#!/bin/bash
echo "=== Setting up Splenic Length Measurement Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Set up directories
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"

mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$SCREENSHOT_DIR"

# Clean any previous results
rm -f "$EXPORTS_DIR/splenic_measurement.json" 2>/dev/null || true
rm -f /tmp/splenic_task_result.json 2>/dev/null || true

# Record initial screenshot count
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# Prepare AMOS data
echo "Preparing abdominal CT data..."
export AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "amos_0001"

# Get the case ID
CASE_ID=$(cat /tmp/amos_case_id 2>/dev/null || echo "amos_0001")
echo "Using case: $CASE_ID"
echo "$CASE_ID" > /tmp/splenic_case_id.txt

# Compute spleen ground truth if not exists
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_spleen_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "Computing spleen ground truth measurements..."
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

case_id = "$CASE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
amos_dir = "$AMOS_DIR"

label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
if not os.path.exists(label_path):
    print(f"ERROR: Label file not found: {label_path}")
    sys.exit(1)

print(f"Loading label map from {label_path}...")
labels = nib.load(label_path)
label_data = labels.get_fdata().astype(np.int32)
spacing = labels.header.get_zooms()[:3]

print(f"Label map shape: {label_data.shape}")
print(f"Voxel spacing: {spacing}")
print(f"Unique labels: {np.unique(label_data)}")

# AMOS label 1 is spleen
spleen_mask = (label_data == 1)
spleen_voxels = np.sum(spleen_mask)
print(f"Spleen voxels (label 1): {spleen_voxels}")

# If no spleen with label 1, check other labels
if spleen_voxels == 0:
    print("WARNING: No voxels with label 1. Checking other labels...")
    for label_val in [2, 3, 4, 5]:
        count = np.sum(label_data == label_val)
        if count > 1000:
            print(f"  Label {label_val}: {count} voxels")
    # Use largest non-zero label as fallback
    for label_val in sorted(np.unique(label_data[label_data > 0]), reverse=True):
        if np.sum(label_data == label_val) > 5000:
            spleen_mask = (label_data == label_val)
            print(f"Using label {label_val} as spleen proxy")
            break

spleen_coords = np.argwhere(spleen_mask)
if len(spleen_coords) == 0:
    print("ERROR: No spleen voxels found in any label")
    # Create dummy ground truth for task to proceed
    gt_data = {
        "case_id": case_id,
        "craniocaudal_length_mm": 110.0,
        "expected_splenomegaly": False,
        "expected_classification": "Normal",
        "tolerance_percent": 20,
        "voxel_spacing": [float(s) for s in spacing],
        "warning": "No spleen label found - using estimated values"
    }
else:
    # Calculate extents in all directions
    z_coords = spleen_coords[:, 2]
    y_coords = spleen_coords[:, 1]
    x_coords = spleen_coords[:, 0]
    
    z_extent_mm = float((z_coords.max() - z_coords.min() + 1) * spacing[2])
    y_extent_mm = float((y_coords.max() - y_coords.min() + 1) * spacing[1])
    x_extent_mm = float((x_coords.max() - x_coords.min() + 1) * spacing[0])
    
    # Craniocaudal is typically the longest dimension
    max_extent = max(z_extent_mm, y_extent_mm, x_extent_mm)
    
    print(f"Extents - X: {x_extent_mm:.1f}mm, Y: {y_extent_mm:.1f}mm, Z: {z_extent_mm:.1f}mm")
    print(f"Maximum extent (craniocaudal): {max_extent:.1f}mm")
    
    # Volume
    voxel_volume = float(np.prod(spacing))
    volume_ml = float(np.sum(spleen_mask) * voxel_volume / 1000.0)
    
    # Center of mass
    center = spleen_coords.mean(axis=0)
    center_mm = [float(c * s) for c, s in zip(center, spacing)]
    
    # Classification
    if max_extent < 120:
        classification = "Normal"
        splenomegaly = False
    elif max_extent < 150:
        classification = "Mild splenomegaly"
        splenomegaly = True
    else:
        classification = "Marked splenomegaly"
        splenomegaly = True
    
    gt_data = {
        "case_id": case_id,
        "craniocaudal_length_mm": round(max_extent, 1),
        "z_extent_mm": round(z_extent_mm, 1),
        "y_extent_mm": round(y_extent_mm, 1),
        "x_extent_mm": round(x_extent_mm, 1),
        "volume_ml": round(volume_ml, 1),
        "center_mm": [round(c, 1) for c in center_mm],
        "expected_splenomegaly": splenomegaly,
        "expected_classification": classification,
        "tolerance_percent": 15,
        "voxel_spacing": [float(s) for s in spacing]
    }
    
    print(f"Classification: {classification}")
    print(f"Splenomegaly: {splenomegaly}")

gt_path = os.path.join(gt_dir, f"{case_id}_spleen_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF
fi

# Verify ground truth was created
if [ -f "$GT_FILE" ]; then
    echo "Ground truth file exists:"
    cat "$GT_FILE"
else
    echo "WARNING: Ground truth file not created"
fi

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chown -R ga:ga "$SCREENSHOT_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true

# Launch Slicer with the CT volume
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    ls -la "$AMOS_DIR/"
    exit 1
fi

echo "Launching 3D Slicer with: $CT_FILE"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$CT_FILE" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Maximize and focus
sleep 5
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo "Case ID: $CASE_ID"
echo "CT file loaded: $CT_FILE"
echo "Output expected at: $EXPORTS_DIR/splenic_measurement.json"
echo ""
echo "INSTRUCTIONS:"
echo "1. Navigate to the spleen (left upper quadrant)"
echo "2. Use coronal view to see full craniocaudal extent"
echo "3. Use Markups ruler to measure superior to inferior pole"
echo "4. Save measurement JSON to: $EXPORTS_DIR/splenic_measurement.json"
echo "5. Take a screenshot showing the measurement"