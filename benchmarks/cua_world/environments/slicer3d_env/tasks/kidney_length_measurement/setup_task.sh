#!/bin/bash
echo "=== Setting up Bilateral Kidney Length Measurement Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous task outputs
echo "Cleaning up previous outputs..."
rm -f "$AMOS_DIR/right_kidney_length.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/left_kidney_length.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/kidney_report.json" 2>/dev/null || true
rm -f /tmp/kidney_task_result.json 2>/dev/null || true

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# ============================================================
# Prepare AMOS data with kidney segmentations
# ============================================================
echo "Preparing AMOS data with kidney segmentations..."

# First try to run the standard AMOS preparation
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID" 2>/dev/null || true

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Check if we need to add kidneys to the synthetic data
if [ -f "$CT_FILE" ]; then
    echo "CT volume found: $CT_FILE"
else
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi

# Generate kidney segmentations and ground truth if not present
echo "Ensuring kidney segmentations exist..."
python3 << 'PYEOF'
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

from scipy.ndimage import label as scipy_label

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
kidney_gt_path = os.path.join(gt_dir, f"{case_id}_kidney_gt.json")

# Check if ground truth already exists
if os.path.exists(kidney_gt_path):
    print(f"Kidney ground truth already exists: {kidney_gt_path}")
    sys.exit(0)

# Load CT to get dimensions and affine
ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata()
affine = ct_nii.affine
spacing = ct_nii.header.get_zooms()[:3]
print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# Check if labels file exists
if os.path.exists(labels_path):
    print(f"Loading existing labels from {labels_path}")
    labels_nii = nib.load(labels_path)
    labels_data = labels_nii.get_fdata().astype(np.int16)
else:
    print("Creating new labels with kidneys...")
    labels_data = np.zeros(ct_data.shape, dtype=np.int16)

# Check if kidneys already exist in labels (labels 2 and 3)
has_right_kidney = np.any(labels_data == 2)
has_left_kidney = np.any(labels_data == 3)

if not has_right_kidney or not has_left_kidney:
    print("Adding synthetic kidney structures...")
    np.random.seed(42)
    
    nx, ny, nz = ct_data.shape
    Y, X = np.ogrid[:nx, :ny]
    center_x, center_y = nx // 2, ny // 2
    
    # Right kidney (label 2) - typically on left side of image (patient's right)
    # Position: lateral and posterior
    rk_cx = center_x + 45  # Lateral
    rk_cy = center_y + 30  # Posterior
    
    # Kidney dimensions: ~11cm x 5cm x 3cm (length x width x depth)
    # Convert to voxels
    rk_length_vox = 11.0 / (spacing[2] / 10)  # Z direction for synthetic
    rk_width_vox = 5.0 / (spacing[0] / 10)
    rk_depth_vox = 3.0 / (spacing[1] / 10)
    
    # Create ellipsoid for right kidney
    z_center_rk = int(nz * 0.45)  # Slightly inferior
    for z in range(nz):
        z_dist = abs(z - z_center_rk) / (rk_length_vox / 2)
        if z_dist > 1.0:
            continue
        # Scale width based on z position (bean shape)
        scale = np.sqrt(1 - z_dist**2)
        for x in range(nx):
            for y in range(ny):
                x_dist = (x - rk_cx) / (rk_width_vox / 2 * scale)
                y_dist = (y - rk_cy) / (rk_depth_vox / 2 * scale)
                if x_dist**2 + y_dist**2 <= 1.0:
                    labels_data[x, y, z] = 2
    
    # Left kidney (label 3) - on right side of image (patient's left)
    # Typically slightly higher than right
    lk_cx = center_x - 45
    lk_cy = center_y + 25
    
    # Left kidney slightly larger (normal variant)
    lk_length_vox = 11.5 / (spacing[2] / 10)
    lk_width_vox = 5.2 / (spacing[0] / 10)
    lk_depth_vox = 3.2 / (spacing[1] / 10)
    
    z_center_lk = int(nz * 0.50)  # Slightly higher
    for z in range(nz):
        z_dist = abs(z - z_center_lk) / (lk_length_vox / 2)
        if z_dist > 1.0:
            continue
        scale = np.sqrt(1 - z_dist**2)
        for x in range(nx):
            for y in range(ny):
                x_dist = (x - lk_cx) / (lk_width_vox / 2 * scale)
                y_dist = (y - lk_cy) / (lk_depth_vox / 2 * scale)
                if x_dist**2 + y_dist**2 <= 1.0:
                    labels_data[x, y, z] = 3
    
    # Save updated labels
    labels_nii = nib.Nifti1Image(labels_data, affine)
    nib.save(labels_nii, labels_path)
    print(f"Labels saved to {labels_path}")

# ============================================================
# Calculate ground truth kidney lengths using PCA
# ============================================================
def calculate_kidney_length(mask, spacing):
    """Calculate the longest dimension of kidney using PCA."""
    if not np.any(mask):
        return 0.0, [0, 0, 0]
    
    # Get coordinates of all kidney voxels
    coords = np.array(np.where(mask)).T  # Shape: (N, 3)
    
    if len(coords) < 10:
        return 0.0, [0, 0, 0]
    
    # Convert to physical coordinates (mm)
    coords_mm = coords * np.array(spacing)
    
    # Center the coordinates
    centroid = np.mean(coords_mm, axis=0)
    centered = coords_mm - centroid
    
    # PCA to find principal axes
    try:
        from numpy.linalg import svd
        U, S, Vt = svd(centered, full_matrices=False)
        
        # Project onto first principal component (longest axis)
        projections = centered @ Vt[0]
        
        # Length is the range along this axis
        length_mm = np.max(projections) - np.min(projections)
        length_cm = length_mm / 10.0
        
        return float(length_cm), centroid.tolist()
    except Exception as e:
        print(f"PCA failed: {e}")
        # Fallback: use bounding box
        min_coords = np.min(coords_mm, axis=0)
        max_coords = np.max(coords_mm, axis=0)
        extents = max_coords - min_coords
        length_cm = np.max(extents) / 10.0
        return float(length_cm), centroid.tolist()

# Calculate ground truth for both kidneys
right_kidney_mask = (labels_data == 2)
left_kidney_mask = (labels_data == 3)

rk_length, rk_centroid = calculate_kidney_length(right_kidney_mask, spacing)
lk_length, lk_centroid = calculate_kidney_length(left_kidney_mask, spacing)

print(f"Right kidney length: {rk_length:.2f} cm")
print(f"Left kidney length: {lk_length:.2f} cm")
print(f"Asymmetry: {abs(rk_length - lk_length):.2f} cm")

# Clinical classification
def classify_size(length_cm):
    if length_cm < 9.0:
        return "Small"
    elif length_cm <= 12.0:
        return "Normal"
    else:
        return "Large"

asymmetry = abs(rk_length - lk_length)
asymmetry_assessment = "Significant" if asymmetry >= 1.5 else "Normal"

# Save ground truth
gt_data = {
    "case_id": case_id,
    "right_kidney": {
        "length_cm": round(rk_length, 2),
        "classification": classify_size(rk_length),
        "centroid_mm": [round(c, 1) for c in rk_centroid],
        "voxel_count": int(np.sum(right_kidney_mask))
    },
    "left_kidney": {
        "length_cm": round(lk_length, 2),
        "classification": classify_size(lk_length),
        "centroid_mm": [round(c, 1) for c in lk_centroid],
        "voxel_count": int(np.sum(left_kidney_mask))
    },
    "asymmetry": {
        "difference_cm": round(asymmetry, 2),
        "assessment": asymmetry_assessment
    },
    "spacing_mm": [float(s) for s in spacing],
    "ct_shape": list(ct_data.shape)
}

with open(kidney_gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {kidney_gt_path}")
print(json.dumps(gt_data, indent=2))
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_kidney_gt.json" ]; then
    echo "ERROR: Failed to create kidney ground truth!"
    exit 1
fi
echo "Kidney ground truth verified"

# ============================================================
# Create Slicer Python script to load CT
# ============================================================
cat > /tmp/load_kidney_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT for kidney measurement: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set soft tissue window for kidney visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Standard soft tissue window
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Get volume bounds for centering
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center on mid-abdomen (where kidneys are)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal - good for kidney length
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    # Switch to coronal view layout (better for kidney measurement)
    layoutManager = slicer.app.layoutManager()
    layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    print(f"CT loaded with soft tissue window (W=350, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Use coronal view (green) to visualize kidney length")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for kidney measurement task")
PYEOF

# ============================================================
# Launch Slicer
# ============================================================
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_kidney_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/kidney_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Bilateral Kidney Length Measurement"
echo "=========================================="
echo ""
echo "Measure the bipolar length (pole-to-pole) of both kidneys."
echo ""
echo "Instructions:"
echo "  1. Locate the RIGHT kidney (usually more inferior)"
echo "  2. Use coronal or oblique views to see its full length"
echo "  3. Measure superior pole to inferior pole using Markups ruler"
echo "  4. Repeat for the LEFT kidney"
echo "  5. Save measurements and create report"
echo ""
echo "Clinical thresholds:"
echo "  - Small: < 9 cm"
echo "  - Normal: 9-12 cm"
echo "  - Large: > 12 cm"
echo "  - Significant asymmetry: >= 1.5 cm difference"
echo ""
echo "Output files:"
echo "  - ~/Documents/SlicerData/AMOS/right_kidney_length.mrk.json"
echo "  - ~/Documents/SlicerData/AMOS/left_kidney_length.mrk.json"
echo "  - ~/Documents/SlicerData/AMOS/kidney_report.json"
echo ""