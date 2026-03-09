#!/bin/bash
echo "=== Setting up Bladder Volume Assessment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Ensure directories exist
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 abdominal CT data..."
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

# ============================================================
# Extract bladder-specific ground truth from AMOS labels
# ============================================================
echo "Extracting bladder ground truth..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")

# Load the full label map
labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
if not os.path.exists(labels_path):
    print(f"ERROR: Labels file not found at {labels_path}")
    sys.exit(1)

print(f"Loading labels from {labels_path}")
labels_nii = nib.load(labels_path)
labels_data = labels_nii.get_fdata().astype(np.int16)
spacing = labels_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(spacing))

print(f"Label volume shape: {labels_data.shape}")
print(f"Voxel spacing: {spacing} mm")
print(f"Labels present: {np.unique(labels_data)}")

# AMOS label 11 is bladder
bladder_mask = (labels_data == 11)

# If no bladder label exists, create synthetic bladder for testing
if not np.any(bladder_mask):
    print("No bladder label (11) found, creating synthetic bladder...")
    shape = labels_data.shape
    center_x, center_y = shape[0] // 2, shape[1] // 2
    
    # Bladder in lower portion of volume (pelvis)
    bladder_z_start = int(shape[2] * 0.08)
    bladder_z_end = int(shape[2] * 0.22)
    
    Y, X = np.ogrid[:shape[0], :shape[1]]
    
    # Create ellipsoidal bladder with random fullness
    np.random.seed(42)
    # Random size variation for realistic bladder volumes (200-700 mL range)
    size_factor = np.random.uniform(0.8, 1.4)
    bladder_radius_x = int(25 * size_factor)
    bladder_radius_y = int(22 * size_factor)
    bladder_center_y = center_y - 15  # Anterior position
    
    for z in range(bladder_z_start, bladder_z_end):
        # Ellipsoidal shape with z-dependent radius
        z_center = (bladder_z_start + bladder_z_end) / 2
        z_factor = 1.0 - 0.6 * ((z - z_center) / ((bladder_z_end - bladder_z_start) / 2)) ** 2
        if z_factor > 0:
            rx = bladder_radius_x * np.sqrt(z_factor)
            ry = bladder_radius_y * np.sqrt(z_factor)
            bladder_slice = ((X - center_x)**2 / (rx**2 + 0.01) + (Y - bladder_center_y)**2 / (ry**2 + 0.01)) <= 1.0
            # Don't overwrite existing organs
            labels_data[:, :, z][bladder_slice & (labels_data[:, :, z] == 0)] = 11
    
    bladder_mask = (labels_data == 11)
    
    # Save updated labels
    updated_nii = nib.Nifti1Image(labels_data, labels_nii.affine, labels_nii.header)
    nib.save(updated_nii, labels_path)
    print(f"Created synthetic bladder with {np.sum(bladder_mask)} voxels")

# Extract bladder-only segmentation for ground truth
bladder_only = bladder_mask.astype(np.int16)
bladder_nii = nib.Nifti1Image(bladder_only, labels_nii.affine, labels_nii.header)
bladder_gt_path = os.path.join(gt_dir, f"{case_id}_bladder_gt.nii.gz")
nib.save(bladder_nii, bladder_gt_path)
print(f"Bladder ground truth saved: {bladder_gt_path}")

# Calculate ground truth volume and statistics
bladder_voxels = int(np.sum(bladder_mask))
bladder_volume_mm3 = bladder_voxels * voxel_volume_mm3
bladder_volume_ml = bladder_volume_mm3 / 1000.0

# Find centroid
coords = np.argwhere(bladder_mask)
if len(coords) > 0:
    centroid_voxels = coords.mean(axis=0)
    centroid_mm = [float(c * s) for c, s in zip(centroid_voxels, spacing)]
else:
    centroid_mm = [0.0, 0.0, 0.0]

# Determine clinical classification
if bladder_volume_ml < 300:
    classification = "Normal"
    clinical_sig = False
elif bladder_volume_ml < 500:
    classification = "Mildly Distended"
    clinical_sig = False
elif bladder_volume_ml < 800:
    classification = "Moderately Distended"
    clinical_sig = True
else:
    classification = "Severely Distended"
    clinical_sig = True

gt_info = {
    "case_id": case_id,
    "bladder_voxels": bladder_voxels,
    "voxel_volume_mm3": round(voxel_volume_mm3, 6),
    "bladder_volume_ml": round(bladder_volume_ml, 1),
    "centroid_mm": [round(c, 2) for c in centroid_mm],
    "expected_classification": classification,
    "expected_clinical_significance": clinical_sig,
    "spacing_mm": [float(s) for s in spacing],
    "volume_range_acceptable_ml": [
        round(bladder_volume_ml * 0.6, 1),
        round(bladder_volume_ml * 1.4, 1)
    ]
}

gt_json_path = os.path.join(gt_dir, f"{case_id}_bladder_gt.json")
with open(gt_json_path, 'w') as f:
    json.dump(gt_info, f, indent=2)

print(f"\nBladder ground truth statistics:")
print(f"  Volume: {bladder_volume_ml:.1f} mL")
print(f"  Classification: {classification}")
print(f"  Clinical significance: {clinical_sig}")
print(f"  Centroid (mm): {centroid_mm}")
print(f"  Ground truth JSON: {gt_json_path}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_bladder_gt.json" ]; then
    echo "ERROR: Ground truth not created!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clean up any previous task outputs
echo "Cleaning up previous task outputs..."
rm -f "$AMOS_DIR/bladder_segmentation.nii.gz" 2>/dev/null || true
rm -f "$AMOS_DIR/bladder_segmentation.nii" 2>/dev/null || true
rm -f "$AMOS_DIR/bladder_report.json" 2>/dev/null || true
rm -f /tmp/bladder_task_result.json 2>/dev/null || true

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true

# Create a Slicer Python script to load the CT and navigate to pelvis
cat > /tmp/load_amos_bladder.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading abdominal CT for bladder assessment: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set soft tissue window/level (good for pelvic structures)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to pelvis (lower portion of the volume where bladder is)
    bounds = [0] * 6
    volume_node.GetBounds(bounds)
    
    # Bladder is typically in the lower 20% of abdominal CT (pelvis)
    z_range = bounds[5] - bounds[4]
    pelvis_z = bounds[4] + z_range * 0.15  # 15% from bottom
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        if color == "Red":
            # Axial view - show pelvis level
            sliceNode.SetSliceOffset(pelvis_z)
        elif color == "Green":
            # Coronal view - center
            center_y = (bounds[2] + bounds[3]) / 2
            sliceNode.SetSliceOffset(center_y)
        else:
            # Sagittal view - center
            center_x = (bounds[0] + bounds[1]) / 2
            sliceNode.SetSliceOffset(center_x)
    
    print(f"CT loaded with soft tissue window (W=400, L=50)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Navigated to pelvis level (z={pelvis_z:.1f})")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for bladder volume assessment task")
PYEOF

# Set environment variables for Python script
export CT_FILE CASE_ID

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_amos_bladder.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for optimal agent interaction
echo "Configuring Slicer window..."
sleep 3

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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/bladder_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Urinary Bladder Volume and Distension Assessment"
echo "======================================================="
echo ""
echo "A urologist needs to assess bladder volume for a patient with"
echo "suspected urinary retention."
echo ""
echo "Your goal:"
echo "  1. Navigate to the pelvis and locate the urinary bladder"
echo "     (fluid-filled midline structure, typically 0-20 HU)"
echo "  2. Open Segment Editor and create a segment named 'Bladder'"
echo "  3. Segment the complete bladder using appropriate tools"
echo "  4. Use Segment Statistics to calculate volume"
echo "  5. Save segmentation and create report"
echo ""
echo "Clinical classification:"
echo "  - Normal: < 300 mL"
echo "  - Mildly Distended: 300-500 mL"
echo "  - Moderately Distended: 500-800 mL"
echo "  - Severely Distended: > 800 mL"
echo ""
echo "Save outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/AMOS/bladder_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/AMOS/bladder_report.json"
echo ""