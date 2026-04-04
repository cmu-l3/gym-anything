#!/bin/bash
echo "=== Setting up Tracheal Measurement Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Prepare LIDC data
echo "Preparing LIDC chest CT data..."
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || {
    echo "WARNING: LIDC data preparation had issues, checking if we can proceed..."
}

# Check if patient ID was adjusted
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

echo "Using patient: $PATIENT_ID"

# Find the CT data - could be DICOM or NIfTI
CT_FILE=""
DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
NIFTI_FILE="$LIDC_DIR/${PATIENT_ID}.nii.gz"

if [ -d "$DICOM_DIR" ] && [ "$(ls -1 "$DICOM_DIR" 2>/dev/null | wc -l)" -gt 10 ]; then
    CT_FILE="$DICOM_DIR"
    echo "Found DICOM directory: $CT_FILE"
elif [ -f "$NIFTI_FILE" ]; then
    CT_FILE="$NIFTI_FILE"
    echo "Found NIfTI file: $CT_FILE"
else
    # Generate synthetic chest CT with trachea if no real data
    echo "Generating synthetic chest CT with airway..."
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
patient_id = "LIDC-IDRI-0001"

os.makedirs(lidc_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

np.random.seed(42)

# Create realistic chest CT dimensions
nx, ny, nz = 512, 512, 200
spacing = (0.7, 0.7, 2.5)  # mm per voxel

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize with air (-1000 HU)
ct_data = np.ones((nx, ny, nz), dtype=np.int16) * -1000

# Create body ellipse (soft tissue ~40 HU)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

body_a, body_b = 180, 140  # Semi-axes of body ellipse
body_mask = ((X - center_x)**2 / body_a**2 + (Y - center_y)**2 / body_b**2) <= 1.0

# Fill body with soft tissue
for z in range(nz):
    ct_data[:, :, z][body_mask] = np.random.normal(40, 15, np.sum(body_mask)).astype(np.int16)

# Create spine (posterior, high density ~400 HU)
spine_cx, spine_cy = center_x, center_y + 100
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 20**2
    ct_data[:, :, z][spine_mask & body_mask] = np.random.normal(400, 50, np.sum(spine_mask & body_mask)).astype(np.int16)

# Create trachea - cylindrical airway anterior to spine
# Normal adult trachea: 15-25mm diameter, we'll make it ~18mm
trachea_cx, trachea_cy = center_x, center_y + 60  # Anterior to spine
trachea_radius_mm = 9.0  # ~18mm diameter
trachea_radius_voxels = trachea_radius_mm / spacing[0]

# Trachea extends from top to carina (around z=120 in our coordinate system)
carina_z = 120  # Slice where trachea bifurcates

# Create trachea mask
trachea_mask = np.zeros((nx, ny, nz), dtype=bool)

for z in range(carina_z, nz):
    # Slight variation in position and size along z
    z_factor = 1.0 + 0.05 * np.sin(z / 20.0)  # Small wobble
    current_radius = trachea_radius_voxels * z_factor
    
    trachea_slice = ((X - trachea_cx)**2 + (Y - trachea_cy)**2) <= current_radius**2
    trachea_mask[:, :, z] = trachea_slice & body_mask
    
    # Fill with air (-1000 HU)
    ct_data[:, :, z][trachea_slice & body_mask] = -1000

# Create main bronchi below carina
left_bronchus_cx = center_x - 30
right_bronchus_cx = center_x + 30
bronchus_cy = trachea_cy - 5
bronchus_radius = trachea_radius_voxels * 0.7

for z in range(max(0, carina_z - 30), carina_z):
    # Left main bronchus
    left_mask = ((X - left_bronchus_cx)**2 + (Y - bronchus_cy)**2) <= bronchus_radius**2
    ct_data[:, :, z][left_mask & body_mask] = -1000
    
    # Right main bronchus
    right_mask = ((X - right_bronchus_cx)**2 + (Y - bronchus_cy)**2) <= bronchus_radius**2
    ct_data[:, :, z][right_mask & body_mask] = -1000

# Add lung tissue (low density, -700 to -500 HU)
lung_left_cx = center_x - 80
lung_right_cx = center_x + 80
lung_cy = center_y - 20
lung_a, lung_b = 80, 100

for z in range(20, 160):
    # Left lung
    left_lung = ((X - lung_left_cx)**2 / lung_a**2 + (Y - lung_cy)**2 / lung_b**2) <= 1.0
    # Right lung  
    right_lung = ((X - lung_right_cx)**2 / lung_a**2 + (Y - lung_cy)**2 / lung_b**2) <= 1.0
    
    # Exclude trachea/bronchi from lung fill
    lung_tissue = (left_lung | right_lung) & body_mask & ~trachea_mask[:, :, z]
    ct_data[:, :, z][lung_tissue] = np.random.normal(-650, 80, np.sum(lung_tissue)).astype(np.int16)

# Save CT volume
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(lidc_dir, f"{patient_id}.nii.gz")
nib.save(ct_img, ct_path)
print(f"Chest CT saved: {ct_path} (shape: {ct_data.shape})")

# Compute ground truth tracheal measurements
# Find mid-trachea slice (between carina and top)
mid_trachea_z = (carina_z + nz) // 2

# Measure trachea at mid-trachea level
trachea_slice = trachea_mask[:, :, mid_trachea_z]
if np.any(trachea_slice):
    rows = np.any(trachea_slice, axis=1)
    cols = np.any(trachea_slice, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    
    ap_diameter_voxels = rmax - rmin + 1
    transverse_diameter_voxels = cmax - cmin + 1
    
    ap_diameter_mm = ap_diameter_voxels * spacing[0]
    transverse_diameter_mm = transverse_diameter_voxels * spacing[1]
    
    # Area-equivalent diameter
    area_pixels = np.sum(trachea_slice)
    area_mm2 = area_pixels * spacing[0] * spacing[1]
    equiv_diameter_mm = 2 * np.sqrt(area_mm2 / np.pi)
    
    mean_diameter_mm = (ap_diameter_mm + transverse_diameter_mm) / 2
else:
    ap_diameter_mm = 18.0
    transverse_diameter_mm = 18.0
    equiv_diameter_mm = 18.0
    mean_diameter_mm = 18.0

# Calculate recommended ETT size
# Rule: ETT OD should be 2-3mm less than tracheal diameter
# ETT OD ≈ ETT ID + 2mm
# So ETT ID ≈ tracheal_diameter - 4 to 5mm
ett_id_calc = mean_diameter_mm - 4.5

# Round to nearest standard size
standard_sizes = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0]
recommended_ett = min(standard_sizes, key=lambda x: abs(x - ett_id_calc))

# Determine trachea shape
if abs(ap_diameter_mm - transverse_diameter_mm) < 2:
    trachea_shape = "circular"
else:
    trachea_shape = "oval"

# Save ground truth
gt_data = {
    "patient_id": patient_id,
    "measurement_slice_z": int(mid_trachea_z),
    "measurement_z_mm": float(mid_trachea_z * spacing[2]),
    "carina_slice_z": int(carina_z),
    "tracheal_diameter_mm": float(round(mean_diameter_mm, 1)),
    "ap_diameter_mm": float(round(ap_diameter_mm, 1)),
    "transverse_diameter_mm": float(round(transverse_diameter_mm, 1)),
    "equiv_diameter_mm": float(round(equiv_diameter_mm, 1)),
    "trachea_shape": trachea_shape,
    "recommended_ett_size_mm": float(recommended_ett),
    "trachea_center_x_voxel": int(trachea_cx),
    "trachea_center_y_voxel": int(trachea_cy),
    "voxel_spacing_mm": list(spacing),
    "abnormalities": "none"
}

gt_path = os.path.join(gt_dir, f"{patient_id}_trachea_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved: {gt_path}")
print(f"  Tracheal diameter: {mean_diameter_mm:.1f} mm")
print(f"  Recommended ETT: {recommended_ett} mm")
print(f"  Measurement slice: z={mid_trachea_z}")
PYEOF
    
    CT_FILE="$LIDC_DIR/${PATIENT_ID}.nii.gz"
fi

# Verify CT file exists
if [ ! -f "$CT_FILE" ] && [ ! -d "$CT_FILE" ]; then
    echo "ERROR: CT data not found at $CT_FILE"
    exit 1
fi
echo "CT data found: $CT_FILE"

# Verify ground truth exists
GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_trachea_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state - remove any existing output files
rm -f /tmp/tracheal_task_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/tracheal_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/tracheal_report.json" 2>/dev/null || true

# Create Slicer Python script to load the CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
patient_id = "$PATIENT_ID"

print(f"Loading chest CT scan: {patient_id}...")

# Check if DICOM or NIfTI
if os.path.isdir(ct_path):
    # DICOM directory
    print("Loading from DICOM directory...")
    from DICOMLib import DICOMUtils
    loadedNodeIDs = []
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(ct_path, db)
        patientUIDs = db.patients()
        for patientUID in patientUIDs:
            loadedNodeIDs.extend(DICOMUtils.loadPatientByUID(patientUID))
    if loadedNodeIDs:
        volume_node = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])
    else:
        print("WARNING: Could not load DICOM")
        volume_node = None
else:
    # NIfTI file
    volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set lung window (to see airways)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Lung window: W=1500, L=-500 (good for airways)
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-500)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to upper chest (where trachea is)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center on upper part of the volume (trachea region)
    center_x = (bounds[0] + bounds[1]) / 2
    center_y = (bounds[2] + bounds[3]) / 2
    upper_z = bounds[4] + (bounds[5] - bounds[4]) * 0.7  # Upper 30% of volume
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(upper_z)
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center_y)
        else:  # Sagittal
            sliceNode.SetSliceOffset(center_x)
    
    print(f"CT loaded with lung window (W=1500, L=-500)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Navigated to upper chest region")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for tracheal measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/tracheal_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tracheal Diameter Measurement for Intubation Planning"
echo "============================================================"
echo ""
echo "You are given a chest CT scan. Measure the tracheal diameter"
echo "to help the anesthesiologist select the correct ETT size."
echo ""
echo "Steps:"
echo "  1. Locate the trachea (air-filled tube, very dark/black)"
echo "  2. Find the carina (where trachea splits into bronchi)"
echo "  3. Go 2-3 cm above carina to mid-trachea level"
echo "  4. Measure inner tracheal diameter using ruler tool"
echo "  5. Recommend ETT size (standard: 6.0-8.5mm ID)"
echo ""
echo "ETT sizing rule:"
echo "  ETT outer diameter = ETT inner diameter + 2mm"
echo "  ETT OD should be 2-3mm less than tracheal diameter"
echo ""
echo "Save outputs to:"
echo "  - Measurement: ~/Documents/SlicerData/LIDC/tracheal_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/tracheal_report.json"
echo ""