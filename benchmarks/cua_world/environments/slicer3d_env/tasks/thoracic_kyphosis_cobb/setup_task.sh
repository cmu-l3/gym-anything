#!/bin/bash
echo "=== Setting up Thoracic Kyphosis Cobb Angle Measurement Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0003"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Clean up any previous task results
rm -f "$LIDC_DIR/kyphosis_landmarks.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/kyphosis_report.json" 2>/dev/null || true
rm -f "$LIDC_DIR/kyphosis_screenshot.png" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Prepare chest CT data
echo "Preparing chest CT data with thoracic spine..."

# Try to download LIDC data or generate synthetic
if ! bash /workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" 2>/dev/null; then
    echo "LIDC download unavailable, generating synthetic chest CT with spine..."
fi

# Generate synthetic chest CT with thoracic spine if needed
CT_FILE="$LIDC_DIR/${PATIENT_ID}_chest.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "Generating synthetic chest CT with thoracic spine..."
    
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

lidc_dir = "/home/ga/Documents/SlicerData/LIDC"
gt_dir = "/var/lib/slicer/ground_truth"
patient_id = "LIDC-IDRI-0003"

os.makedirs(lidc_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

np.random.seed(42)

# Chest CT volume parameters
nx, ny, nz = 512, 512, 200
spacing = (0.7, 0.7, 2.5)  # mm per voxel

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Create CT volume with realistic HU values
ct_data = np.zeros((nx, ny, nz), dtype=np.int16)
ct_data[:] = -1000  # Air background

# Create body outline
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Chest cavity with soft tissue
for z in range(nz):
    body_mask = ((X - center_x)**2 / (180**2) + (Y - center_y)**2 / (130**2)) <= 1.0
    ct_data[:, :, z][body_mask] = np.random.normal(40, 15, (np.sum(body_mask),)).astype(np.int16)
    
    # Lung fields
    lung_left = ((X - (center_x - 80))**2 / (55**2) + (Y - center_y)**2 / (85**2)) <= 1.0
    lung_right = ((X - (center_x + 80))**2 / (55**2) + (Y - center_y)**2 / (85**2)) <= 1.0
    lungs = (lung_left | lung_right) & body_mask
    ct_data[:, :, z][lungs] = np.random.normal(-850, 50, (np.sum(lungs),)).astype(np.int16)

# Create thoracic spine with kyphotic curvature
spine_center_x = center_x
spine_center_y = center_y + 100  # Posterior position

# Kyphosis parameters - create a curve with approximately 38 degrees Cobb angle
n_vertebrae = 12  # T1-T12
vertebra_height_mm = 22
disc_height_mm = 5
total_spine_z = n_vertebrae * (vertebra_height_mm + disc_height_mm)
spine_start_z = (nz * spacing[2] - total_spine_z) / 2

# Kyphosis curve parameters
kyphosis_apex_fraction = 0.45  # Apex around T5-T6
kyphosis_max_offset = 22  # mm forward at apex

vertebra_info = []

for v in range(n_vertebrae):
    vert_name = f"T{v+1}"
    z_start_mm = spine_start_z + v * (vertebra_height_mm + disc_height_mm)
    z_end_mm = z_start_mm + vertebra_height_mm
    
    z_start = int(z_start_mm / spacing[2])
    z_end = int(z_end_mm / spacing[2])
    z_end = min(z_end, nz)
    
    # Calculate kyphotic curve offset
    z_center_mm = (z_start_mm + z_end_mm) / 2
    normalized_pos = (z_center_mm - spine_start_z) / total_spine_z
    
    # Parabolic kyphosis curve
    curve_offset = kyphosis_max_offset * np.sin(np.pi * normalized_pos)
    
    # Vertebral body center
    vb_center_y = spine_center_y - curve_offset / spacing[1]
    
    # Calculate local endplate angle (derivative of curve)
    if 0 < normalized_pos < 1:
        angle_rad = (np.pi * kyphosis_max_offset / total_spine_z) * np.cos(np.pi * normalized_pos)
        angle_deg = np.degrees(angle_rad)
    else:
        angle_deg = 0
    
    vertebra_info.append({
        'name': vert_name,
        'z_start_mm': float(z_start_mm),
        'z_end_mm': float(z_end_mm),
        'z_slice_center': int((z_start + z_end) / 2),
        'center_y_voxel': float(vb_center_y),
        'center_y_mm': float(vb_center_y * spacing[1]),
        'kyphosis_offset_mm': float(curve_offset),
        'endplate_angle_deg': float(angle_deg)
    })
    
    # Draw vertebral body
    for z in range(z_start, z_end):
        if z >= nz:
            break
        # Vertebral body (rectangular-ish, bone density)
        vb_mask = ((X - spine_center_x)**2 / (18**2) + (Y - vb_center_y)**2 / (14**2)) <= 1.0
        ct_data[:, :, z][vb_mask] = np.random.normal(350, 80, (np.sum(vb_mask),)).astype(np.int16)
        
        # Spinous process
        sp_y = vb_center_y + 28
        sp_mask = ((X - spine_center_x)**2 / (6**2) + (Y - sp_y)**2 / (20**2)) <= 1.0
        ct_data[:, :, z][sp_mask] = np.random.normal(400, 100, (np.sum(sp_mask),)).astype(np.int16)
        
        # Transverse processes and pedicles
        for side in [-1, 1]:
            ped_x = spine_center_x + side * 22
            ped_mask = ((X - ped_x)**2 + (Y - (vb_center_y + 8))**2) <= 6**2
            ct_data[:, :, z][ped_mask] = np.random.normal(380, 80, (np.sum(ped_mask),)).astype(np.int16)

# Calculate ground truth Cobb angle
# T4 superior endplate to T12 inferior endplate
t4_info = vertebra_info[3]  # T4
t12_info = vertebra_info[11]  # T12

# Cobb angle calculation: sum of angles at endpoints
# For a sine curve y = A*sin(pi*x/L), the Cobb angle is approximately 2*arctan(A*pi/L)
A = kyphosis_max_offset
L = total_spine_z
cobb_angle = 2 * np.degrees(np.arctan(A * np.pi / L))

# Add small random variation for realism
cobb_angle = round(cobb_angle + np.random.normal(0, 0.5), 1)

# Classification
if cobb_angle < 20:
    classification = "Hypokyphotic"
elif cobb_angle <= 45:
    classification = "Normal"
else:
    classification = "Hyperkyphotic"

# Save CT volume
ct_img = nib.Nifti1Image(ct_data.astype(np.int16), affine)
ct_path = os.path.join(lidc_dir, f"{patient_id}_chest.nii.gz")
nib.save(ct_img, ct_path)
print(f"Chest CT saved: {ct_path}")
print(f"Shape: {ct_data.shape}, Spacing: {spacing}")

# Save ground truth
ground_truth = {
    "patient_id": patient_id,
    "cobb_angle_degrees": cobb_angle,
    "classification": classification,
    "measurement_method": "T4_superior_to_T12_inferior",
    "superior_vertebra": "T4",
    "inferior_vertebra": "T12",
    "acceptable_superior_range": ["T3", "T4", "T5"],
    "acceptable_inferior_range": ["T10", "T11", "T12"],
    "angle_tolerance_degrees": 8,
    "vertebrae": vertebra_info,
    "image_info": {
        "shape": list(ct_data.shape),
        "spacing_mm": list(spacing),
        "spine_location": {
            "center_x_voxel": int(spine_center_x),
            "center_y_voxel": int(spine_center_y),
            "z_range_voxels": [int(spine_start_z / spacing[2]), int((spine_start_z + total_spine_z) / spacing[2])]
        }
    },
    "kyphosis_parameters": {
        "apex_offset_mm": float(kyphosis_max_offset),
        "apex_location_fraction": float(kyphosis_apex_fraction)
    }
}

gt_path = os.path.join(gt_dir, f"{patient_id}_kyphosis_gt.json")
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved: {gt_path}")
print(f"Cobb angle: {cobb_angle}° ({classification})")
print(f"Measurement landmarks: T4 superior to T12 inferior")
PYEOF
fi

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Verify ground truth exists
GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_kyphosis_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth not found at $GT_FILE"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Save patient ID for export script
echo "$PATIENT_ID" > /tmp/kyphosis_patient_id

# Create Slicer Python script to load CT and set up sagittal view
cat > /tmp/load_chest_ct.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get('CT_FILE', '/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0003_chest.nii.gz')

print(f"Loading chest CT: {ct_path}")

# Load volume
volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set bone window for spine visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(2000)  # Wide window for bone
        displayNode.SetLevel(300)    # Center on bone
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Get volume bounds
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center on data and set up initial view
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        # Center coordinates
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        elif color == "Yellow":  # Sagittal - this is key for kyphosis
            sliceNode.SetSliceOffset(center[0])
    
    # Set to conventional layout first, then switch to one with good sagittal
    slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    slicer.util.resetSliceViews()
    
    print(f"CT loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Window/Level set for bone visualization (W=2000, L=300)")
    print(f"Navigate to SAGITTAL view (Yellow slice) to see the spine curvature")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete - ready for kyphosis measurement task")
PYEOF

# Set environment variable for the Python script
export CT_FILE="$CT_FILE"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 3

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Give extra time for volume to load
sleep 10

# Maximize and focus Slicer window
echo "Configuring Slicer window..."
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Thoracic Kyphosis Cobb Angle Measurement"
echo "=============================================="
echo ""
echo "You are given a chest CT scan showing the thoracic spine."
echo ""
echo "Your goal:"
echo "  1. Navigate to SAGITTAL view for spine visualization"
echo "  2. Identify the most tilted SUPERIOR vertebra (T3-T5)"
echo "  3. Identify the most tilted INFERIOR vertebra (T10-T12)"
echo "  4. Using Markups, place lines on vertebral endplates"
echo "  5. Measure the Cobb angle between these lines"
echo "  6. Classify: Hypokyphotic (<20°), Normal (20-45°), Hyperkyphotic (>45°)"
echo ""
echo "Save your outputs:"
echo "  - Landmarks: ~/Documents/SlicerData/LIDC/kyphosis_landmarks.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/kyphosis_report.json"
echo ""
echo "Report JSON must contain:"
echo "  - superior_vertebra (e.g., 'T4')"
echo "  - inferior_vertebra (e.g., 'T12')"
echo "  - cobb_angle_degrees (number)"
echo "  - classification ('Hypokyphotic', 'Normal', or 'Hyperkyphotic')"
echo ""