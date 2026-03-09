#!/bin/bash
echo "=== Setting up Renal Parenchymal Thickness Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 data..."
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
echo "CT volume found: $CT_FILE"

# Calculate ground truth parenchymal thickness from kidney labels
echo "Calculating ground truth parenchymal thickness..."
python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
    from scipy.ndimage import distance_transform_edt, center_of_mass, binary_erosion
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
    import nibabel as nib
    from scipy.ndimage import distance_transform_edt, center_of_mass, binary_erosion

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

# Load CT and labels
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

if not os.path.exists(label_path):
    print(f"Warning: Label file not found at {label_path}")
    # Create default ground truth
    measurements = {
        "right_kidney": {
            "anterior_mm": 15.0,
            "posterior_mm": 14.0,
            "lateral_mm": 16.0,
            "average_mm": 15.0,
            "expected_classification": "Normal"
        },
        "left_kidney": {
            "anterior_mm": 14.5,
            "posterior_mm": 14.0,
            "lateral_mm": 15.5,
            "average_mm": 14.7,
            "expected_classification": "Mildly reduced"
        },
        "bilateral_difference_mm": 0.3,
        "expected_symmetry": "Symmetric"
    }
else:
    ct_nii = nib.load(ct_path)
    ct_data = ct_nii.get_fdata()
    spacing = ct_nii.header.get_zooms()[:3]
    
    label_nii = nib.load(label_path)
    label_data = label_nii.get_fdata().astype(np.int16)
    
    # AMOS labels: 2 = right kidney, 3 = left kidney
    measurements = {}
    
    for kidney_name, kidney_label in [("right_kidney", 2), ("left_kidney", 3)]:
        kidney_mask = (label_data == kidney_label)
        
        if not np.any(kidney_mask):
            print(f"Warning: {kidney_name} not found in labels, using defaults")
            measurements[kidney_name] = {
                "anterior_mm": 15.0,
                "posterior_mm": 14.0,
                "lateral_mm": 16.0,
                "average_mm": 15.0,
                "expected_classification": "Normal"
            }
            continue
        
        # Find centroid (mid-kidney level)
        com = center_of_mass(kidney_mask)
        mid_z = int(com[2])
        
        # Get the kidney slice at mid-level
        kidney_slice = kidney_mask[:, :, mid_z]
        
        if not np.any(kidney_slice):
            # Try adjacent slices
            for offset in [-1, 1, -2, 2, -3, 3]:
                if 0 <= mid_z + offset < kidney_mask.shape[2]:
                    kidney_slice = kidney_mask[:, :, mid_z + offset]
                    if np.any(kidney_slice):
                        mid_z = mid_z + offset
                        break
        
        if not np.any(kidney_slice):
            measurements[kidney_name] = {
                "anterior_mm": 15.0,
                "posterior_mm": 14.0,
                "lateral_mm": 16.0,
                "average_mm": 15.0,
                "expected_classification": "Normal"
            }
            continue
        
        # Find the centroid of this slice (approximates sinus location)
        slice_com = center_of_mass(kidney_slice)
        cx, cy = int(slice_com[0]), int(slice_com[1])
        
        # Find boundary pixels
        interior = binary_erosion(kidney_slice)
        boundary = kidney_slice & ~interior
        boundary_coords = np.argwhere(boundary)
        
        if len(boundary_coords) < 4:
            measurements[kidney_name] = {
                "anterior_mm": 15.0,
                "posterior_mm": 14.0,
                "lateral_mm": 16.0,
                "average_mm": 15.0,
                "expected_classification": "Normal"
            }
            continue
        
        # Categorize boundary points by position relative to centroid
        boundary_rel = boundary_coords - np.array([cx, cy])
        
        # Define regions (anterior = low y, posterior = high y, lateral = far x)
        anterior_mask = boundary_rel[:, 1] < -3
        posterior_mask = boundary_rel[:, 1] > 3
        lateral_mask = np.abs(boundary_rel[:, 0]) > np.abs(boundary_rel[:, 1])
        
        def get_thickness_at_boundary(mask, boundary_coords, cx, cy, spacing):
            if not np.any(mask):
                return 15.0
            selected = boundary_coords[mask]
            if len(selected) == 0:
                return 15.0
            # Pick the point closest to the centroid line
            distances_to_center = np.linalg.norm(selected - np.array([cx, cy]), axis=1)
            closest_idx = np.argmin(distances_to_center)
            bx, by = selected[closest_idx]
            # Thickness is the distance from this boundary point to the center (sinus)
            thickness = np.sqrt((bx - cx)**2 * spacing[0]**2 + (by - cy)**2 * spacing[1]**2)
            return float(thickness)
        
        anterior_thickness = get_thickness_at_boundary(anterior_mask, boundary_coords, cx, cy, spacing)
        posterior_thickness = get_thickness_at_boundary(posterior_mask, boundary_coords, cx, cy, spacing)
        lateral_thickness = get_thickness_at_boundary(lateral_mask, boundary_coords, cx, cy, spacing)
        
        # Parenchymal thickness is roughly half the total thickness (cortex to sinus)
        correction = 0.55
        
        ant_mm = round(anterior_thickness * correction, 1)
        post_mm = round(posterior_thickness * correction, 1)
        lat_mm = round(lateral_thickness * correction, 1)
        avg_mm = round((ant_mm + post_mm + lat_mm) / 3, 1)
        
        # Ensure reasonable values
        ant_mm = max(8.0, min(25.0, ant_mm))
        post_mm = max(8.0, min(25.0, post_mm))
        lat_mm = max(8.0, min(25.0, lat_mm))
        avg_mm = round((ant_mm + post_mm + lat_mm) / 3, 1)
        
        measurements[kidney_name] = {
            "anterior_mm": ant_mm,
            "posterior_mm": post_mm,
            "lateral_mm": lat_mm,
            "average_mm": avg_mm,
            "mid_slice_z": mid_z,
            "centroid_xy": [cx, cy]
        }
    
    # Calculate expected classification
    for kidney in ["right_kidney", "left_kidney"]:
        avg = measurements[kidney]["average_mm"]
        if avg >= 15:
            measurements[kidney]["expected_classification"] = "Normal"
        elif avg >= 10:
            measurements[kidney]["expected_classification"] = "Mildly reduced"
        else:
            measurements[kidney]["expected_classification"] = "Significantly reduced"
    
    # Bilateral comparison
    bilateral_diff = abs(measurements["right_kidney"]["average_mm"] - measurements["left_kidney"]["average_mm"])
    measurements["bilateral_difference_mm"] = round(bilateral_diff, 1)
    measurements["expected_symmetry"] = "Symmetric" if bilateral_diff <= 5 else "Asymmetric"

# Save ground truth
os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{case_id}_renal_thickness_gt.json")
with open(gt_path, "w") as f:
    json.dump(measurements, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"Right kidney average: {measurements['right_kidney']['average_mm']}mm ({measurements['right_kidney']['expected_classification']})")
print(f"Left kidney average: {measurements['left_kidney']['average_mm']}mm ({measurements['left_kidney']['expected_classification']})")
print(f"Bilateral difference: {measurements['bilateral_difference_mm']}mm ({measurements['expected_symmetry']})")
PYEOF

# Clean up any previous task outputs
rm -f "$AMOS_DIR/renal_thickness_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/renal_parenchyma_report.json" 2>/dev/null || true
rm -f /tmp/renal_task_result.json 2>/dev/null || true

# Create output directory with proper permissions
mkdir -p "$AMOS_DIR"
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true

# Create a Slicer Python script to load the CT with kidney-optimized window
cat > /tmp/load_renal_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading AMOS CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")

    # Set soft tissue window for kidney visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    slicer.util.resetSliceViews()

    # Center on the data - focus on kidney region
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            # Axial - center on mid-abdomen (kidney level)
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

    print(f"CT loaded with soft tissue window (W=350, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for renal parenchymal thickness measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_renal_ct.py > /tmp/slicer_launch.log 2>&1 &

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
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Renal Parenchymal Thickness Assessment"
echo "============================================="
echo ""
echo "You are given an abdominal CT scan. Assess the patient's kidneys for"
echo "evidence of chronic kidney disease (CKD) by measuring parenchymal thickness."
echo ""
echo "For EACH kidney:"
echo "  1. Navigate to the mid-kidney level (at the hilum)"
echo "  2. Measure parenchymal thickness at 3 locations using the Markups ruler:"
echo "     - Anterior: outer cortex to renal sinus, perpendicular"
echo "     - Posterior: outer cortex to renal sinus, perpendicular"
echo "     - Lateral: at lateral convex border, cortex to sinus"
echo ""
echo "Clinical classification (based on average):"
echo "  - Normal: ≥15mm"
echo "  - Mildly reduced: 10-14mm"
echo "  - Significantly reduced: <10mm (suggests CKD)"
echo ""
echo "Bilateral symmetry: >5mm difference = Asymmetric"
echo ""
echo "Save your outputs:"
echo "  - Markups: ~/Documents/SlicerData/AMOS/renal_thickness_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/renal_parenchyma_report.json"
echo ""