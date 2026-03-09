#!/bin/bash
echo "=== Setting up Verify Anatomical Orientation Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clear previous results
rm -f /tmp/orientation_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/orientation_markers.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/all_fiducials.json" 2>/dev/null || true

# Record initial state - no fiducials should exist
echo "0" > /tmp/initial_fiducial_count.txt

# Prepare AMOS data
echo "Preparing AMOS abdominal CT data..."
export CASE_ID AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    ls -la "$AMOS_DIR"
    exit 1
fi

echo "CT file found: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

# Compute reference organ bounding boxes from ground truth labels
echo "Computing reference anatomical positions from ground truth..."
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

case_id = os.environ.get("CASE_ID", "amos_0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")

label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")

if not os.path.exists(label_path):
    print(f"WARNING: Label file not found at {label_path}")
    # Create dummy reference
    reference = {
        "case_id": case_id,
        "has_ground_truth": False,
        "liver_bbox": {"center_ras": [0, 0, 0], "extent_mm": [100, 100, 100]},
        "spine_bbox": {"center_ras": [0, 50, 0], "extent_mm": [50, 50, 200]},
        "heart_region": {"center_ras": [0, 0, 100], "extent_mm": [100, 100, 100]}
    }
else:
    print(f"Loading ground truth labels from {label_path}")
    label_nii = nib.load(label_path)
    label_data = label_nii.get_fdata().astype(np.int32)
    affine = label_nii.affine
    
    # Get voxel spacing
    spacing = np.abs(np.diag(affine)[:3])
    print(f"Voxel spacing: {spacing} mm")
    
    def get_bbox_ras(mask, affine):
        """Get bounding box center and extent in RAS coordinates."""
        if not np.any(mask):
            return None
        
        coords = np.argwhere(mask)
        min_ijk = coords.min(axis=0)
        max_ijk = coords.max(axis=0)
        center_ijk = (min_ijk + max_ijk) / 2.0
        
        # Convert to RAS
        center_ras = nib.affines.apply_affine(affine, center_ijk)
        
        # Get extent in mm
        extent_mm = (max_ijk - min_ijk) * np.abs(np.diag(affine)[:3])
        
        return {
            "center_ras": center_ras.tolist(),
            "min_ras": nib.affines.apply_affine(affine, min_ijk).tolist(),
            "max_ras": nib.affines.apply_affine(affine, max_ijk).tolist(),
            "extent_mm": extent_mm.tolist(),
            "voxel_count": int(np.sum(mask))
        }
    
    # AMOS labels: 1=spleen, 2=right kidney, 3=left kidney, 6=liver, 7=stomach, 
    # 8=aorta, 9=IVC, 10=portal/splenic vein, 11=pancreas, etc.
    # For synthetic data: 1=spleen, 6=liver, 10=aorta
    
    reference = {
        "case_id": case_id,
        "has_ground_truth": True,
        "volume_shape": list(label_data.shape),
        "spacing_mm": spacing.tolist()
    }
    
    # Liver (label 6)
    liver_mask = (label_data == 6)
    if np.any(liver_mask):
        reference["liver_bbox"] = get_bbox_ras(liver_mask, affine)
        print(f"Liver: {reference['liver_bbox']['voxel_count']} voxels, center: {reference['liver_bbox']['center_ras']}")
    else:
        print("WARNING: No liver label found")
        reference["liver_bbox"] = None
    
    # Spine approximation - posterior midline (use aorta location as reference)
    # The spine is posterior to the aorta
    aorta_mask = (label_data == 10) | (label_data == 8)  # aorta or portal vein
    if np.any(aorta_mask):
        aorta_bbox = get_bbox_ras(aorta_mask, affine)
        # Spine is posterior (more positive A in RAS) from aorta
        spine_center = aorta_bbox["center_ras"].copy()
        spine_center[1] += 30  # 30mm posterior from aorta
        reference["spine_bbox"] = {
            "center_ras": spine_center,
            "extent_mm": [40, 40, 150],
            "estimated": True
        }
        print(f"Spine (estimated): center: {spine_center}")
    else:
        # Estimate spine at posterior midline
        center_ijk = np.array(label_data.shape) / 2.0
        center_ijk[1] = label_data.shape[1] * 0.7  # 70% posterior
        spine_center = nib.affines.apply_affine(affine, center_ijk)
        reference["spine_bbox"] = {
            "center_ras": spine_center.tolist(),
            "extent_mm": [40, 40, 150],
            "estimated": True
        }
        print(f"Spine (estimated from shape): center: {spine_center}")
    
    # Heart region - superior to liver, in mediastinum
    # Estimate based on volume dimensions
    if reference.get("liver_bbox"):
        liver_center = reference["liver_bbox"]["center_ras"]
        heart_center = [
            liver_center[0],  # Similar R coordinate (slightly left)
            liver_center[1] - 30,  # More anterior
            liver_center[2] + 100  # Superior (higher S)
        ]
    else:
        center_ijk = np.array(label_data.shape) / 2.0
        center_ijk[2] = label_data.shape[2] * 0.8  # Upper part of volume
        heart_center = nib.affines.apply_affine(affine, center_ijk).tolist()
    
    reference["heart_region"] = {
        "center_ras": heart_center,
        "extent_mm": [120, 100, 80],
        "estimated": True
    }
    print(f"Heart (estimated): center: {heart_center}")
    
    # Store expected relationships for verification
    reference["expected_relationships"] = {
        "liver_on_right": True,  # Liver R coordinate should be negative in RAS
        "spine_posterior": True,  # Spine A coordinate should be most positive
        "heart_superior_to_liver": True  # Heart S > Liver S
    }

# Save reference for verifier
ref_path = os.path.join(gt_dir, f"{case_id}_orientation_ref.json")
with open(ref_path, "w") as f:
    json.dump(reference, f, indent=2)
print(f"\nReference saved to {ref_path}")

# Also save to /tmp for export script
with open("/tmp/orientation_reference.json", "w") as f:
    json.dump(reference, f, indent=2)

PYEOF

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Launch 3D Slicer with the CT data
echo ""
echo "Launching 3D Slicer with CT data..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$CT_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
wait_for_slicer 90

# Maximize and focus
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Wait for data to load
echo "Waiting for CT data to load..."
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Verify anatomical orientation by placing fiducial markers:"
echo "  1. F-Liver - on the liver (patient's right side)"
echo "  2. F-Spine - on a vertebral body (posterior)"
echo "  3. F-Heart - on the heart (if visible in scan)"
echo ""
echo "CT data loaded from: $CT_FILE"
echo "Save markups to: $AMOS_DIR/orientation_markers.mrk.json"