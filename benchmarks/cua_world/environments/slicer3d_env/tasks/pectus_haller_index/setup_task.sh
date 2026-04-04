#!/bin/bash
echo "=== Setting up Pectus Haller Index Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Clean up any previous results
rm -f "$LIDC_DIR/transverse_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/ap_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/haller_index_report.json" 2>/dev/null || true
rm -f /tmp/pectus_task_result.json 2>/dev/null || true

# Prepare LIDC data
echo "Preparing LIDC-IDRI chest CT data..."
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || {
    echo "LIDC download failed, generating synthetic chest CT data..."
}

# Get actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi
echo "$PATIENT_ID" > /tmp/pectus_patient_id

echo "Using patient: $PATIENT_ID"

# Check if we have DICOM data or need to create synthetic NIfTI
CT_LOADED="false"
DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
NIFTI_FILE="$LIDC_DIR/${PATIENT_ID}_chest_ct.nii.gz"

# Generate synthetic chest CT with known Haller Index if no real data
if [ ! -d "$DICOM_DIR" ] || [ "$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)" -lt 10 ]; then
    if [ ! -f "$NIFTI_FILE" ]; then
        echo "Generating synthetic chest CT with known geometry..."
        
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

lidc_dir = os.environ.get("LIDC_DIR", "/home/ga/Documents/SlicerData/LIDC")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

np.random.seed(42)

# Create realistic chest CT dimensions
# Typical thoracic CT: 512x512 in-plane, ~300-400 slices
# Using smaller for speed: 256x256x150
nx, ny, nz = 256, 256, 150
spacing = (0.78, 0.78, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize CT volume with air (-1000 HU)
ct_data = np.full((nx, ny, nz), -1000, dtype=np.int16)

# Define chest geometry
center_x, center_y = nx // 2, ny // 2

# Create meshgrid for distance calculations
Y, X = np.ogrid[:nx, :ny]

# Define pectus excavatum geometry
# Normal chest has transverse ~280mm, AP ~120mm -> HI = 2.33 (normal)
# We'll create mild pectus: transverse ~260mm, AP ~90mm -> HI = 2.89 (mild)

# Chest wall dimensions in voxels
transverse_radius = 130  # ~100mm radius each side = 200mm total internal width -> transverse ~260mm
normal_ap_half = 60  # Normal AP distance
sternal_depression_depth = 15  # Additional depression at sternum level

# Level of maximum sternal depression (slice 75, middle of the scan)
max_depression_slice = 75

# Ground truth measurements
gt_transverse_mm = 0
gt_ap_mm = 0
gt_slice = max_depression_slice

for z in range(nz):
    # Vary the sternal depression along z (Gaussian profile)
    depression_factor = np.exp(-((z - max_depression_slice)**2) / (2 * 30**2))
    current_depression = sternal_depression_depth * depression_factor
    
    # Chest cavity (elliptical)
    # Transverse (x) is wider, AP (y) varies with depression
    chest_a = transverse_radius  # Semi-major axis (transverse)
    chest_b = normal_ap_half - current_depression  # Semi-minor axis (AP, reduced at depression)
    
    # Create elliptical chest wall
    chest_mask = ((X - center_x)**2 / (chest_a**2) + (Y - center_y)**2 / (chest_b**2)) <= 1.0
    
    # Inner lung regions (slightly smaller ellipse)
    lung_a = chest_a - 15
    lung_b = chest_b - 10
    lung_mask = ((X - center_x)**2 / (lung_a**2) + (Y - center_y)**2 / (lung_b**2)) <= 1.0
    
    # Sternum (anterior, along midline)
    sternum_width = 15
    sternum_depth = 8
    sternum_y = center_y - chest_b + 5 + current_depression  # Pushed posteriorly at depression
    sternum_mask = (np.abs(X - center_x) < sternum_width) & (Y < sternum_y) & (Y > sternum_y - sternum_depth)
    
    # Spine (posterior)
    spine_cx, spine_cy = center_x, center_y + chest_b - 15
    spine_radius = 12
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= spine_radius**2
    
    # Ribs (curved along chest wall)
    rib_mask = chest_mask & ~lung_mask
    
    # Fill in HU values
    # Soft tissue background inside chest
    ct_data[:, :, z][chest_mask] = np.random.normal(40, 10, np.sum(chest_mask)).astype(np.int16)
    
    # Lungs (air-filled, -800 to -600 HU)
    ct_data[:, :, z][lung_mask] = np.random.normal(-750, 50, np.sum(lung_mask)).astype(np.int16)
    
    # Ribs/chest wall (bone, 200-400 HU)
    ct_data[:, :, z][rib_mask] = np.random.normal(300, 50, np.sum(rib_mask)).astype(np.int16)
    
    # Sternum (bone, 250-400 HU)
    ct_data[:, :, z][sternum_mask] = np.random.normal(350, 40, np.sum(sternum_mask)).astype(np.int16)
    
    # Spine (bone, 300-500 HU)
    ct_data[:, :, z][spine_mask] = np.random.normal(400, 60, np.sum(spine_mask)).astype(np.int16)
    
    # Record ground truth at maximum depression slice
    if z == max_depression_slice:
        # Transverse: internal chest width (inner rib to inner rib)
        gt_transverse_mm = 2 * lung_a * spacing[0]  # mm
        
        # AP: sternum posterior surface to spine anterior surface
        # Distance from posterior sternum to anterior spine
        sternum_posterior_y = sternum_y - sternum_depth
        spine_anterior_y = spine_cy - spine_radius
        gt_ap_mm = (spine_anterior_y - sternum_posterior_y) * spacing[1]  # mm

# Clamp HU values to realistic range
ct_data = np.clip(ct_data, -1024, 3071)

# Save NIfTI
nifti_path = os.path.join(lidc_dir, f"{patient_id}_chest_ct.nii.gz")
ct_img = nib.Nifti1Image(ct_data.astype(np.int16), affine)
nib.save(ct_img, nifti_path)
print(f"Saved chest CT to {nifti_path}")
print(f"Volume shape: {ct_data.shape}, spacing: {spacing}")

# Calculate Haller Index
gt_haller_index = gt_transverse_mm / gt_ap_mm if gt_ap_mm > 0 else 0

# Determine classification
if gt_haller_index < 2.5:
    classification = "Normal"
elif gt_haller_index < 3.2:
    classification = "Mild"
elif gt_haller_index < 3.5:
    classification = "Moderate"
else:
    classification = "Severe"

surgical_candidate = gt_haller_index > 3.25

# Save ground truth
gt_data = {
    "patient_id": patient_id,
    "measurement_slice": int(gt_slice),
    "transverse_diameter_mm": float(round(gt_transverse_mm, 2)),
    "ap_diameter_mm": float(round(gt_ap_mm, 2)),
    "haller_index": float(round(gt_haller_index, 3)),
    "severity_classification": classification,
    "surgical_candidate": surgical_candidate,
    "spacing_mm": list(spacing),
    "volume_shape": list(ct_data.shape)
}

gt_path = os.path.join(gt_dir, f"{patient_id}_haller_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  Transverse: {gt_transverse_mm:.1f} mm")
print(f"  AP: {gt_ap_mm:.1f} mm")
print(f"  Haller Index: {gt_haller_index:.2f}")
print(f"  Classification: {classification}")
print(f"  Surgical candidate: {surgical_candidate}")
PYEOF
        
        CT_LOADED="true"
    fi
fi

# Set environment variables for Python script
export LIDC_DIR GROUND_TRUTH_DIR PATIENT_ID

# Verify data exists
if [ -f "$NIFTI_FILE" ]; then
    echo "Using NIfTI chest CT: $NIFTI_FILE"
    CT_FILE="$NIFTI_FILE"
elif [ -d "$DICOM_DIR" ] && [ "$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)" -gt 10 ]; then
    echo "Using DICOM chest CT: $DICOM_DIR"
    CT_FILE="$DICOM_DIR"
else
    echo "ERROR: No chest CT data available"
    exit 1
fi

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_haller_gt.json" ]; then
    echo "WARNING: Ground truth not found, task may not verify correctly"
fi

# Create Slicer Python script to load the CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

lidc_dir = "$LIDC_DIR"
patient_id = "$PATIENT_ID"
nifti_file = "$NIFTI_FILE"
dicom_dir = "$DICOM_DIR"

print(f"Loading chest CT for patient: {patient_id}")

volume_node = None

# Try NIfTI first
if os.path.exists(nifti_file):
    print(f"Loading NIfTI: {nifti_file}")
    volume_node = slicer.util.loadVolume(nifti_file)
# Fall back to DICOM
elif os.path.isdir(dicom_dir):
    print(f"Loading DICOM from: {dicom_dir}")
    from DICOMLib import DICOMUtils
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicom_dir, db)
        patientUIDs = db.patients()
        if patientUIDs:
            studies = db.studiesForPatient(patientUIDs[0])
            if studies:
                series = db.seriesForStudy(studies[0])
                if series:
                    loadedVolumeNodes = DICOMUtils.loadSeriesByUID([series[0]])
                    if loadedVolumeNodes:
                        volume_node = loadedVolumeNodes[0]

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set bone/chest wall window for pectus assessment
    # Window: 2000, Level: 400 (shows bone and soft tissue well)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(2000)
        displayNode.SetLevel(400)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to approximate level of max sternal depression (middle of scan)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2  # Middle of the volume
    
    # Set axial view (Red) to middle of the scan
    redWidget = slicer.app.layoutManager().sliceWidget("Red")
    redLogic = redWidget.sliceLogic()
    redNode = redLogic.GetSliceNode()
    redNode.SetSliceOffset(center_z)
    
    print(f"Chest CT loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Window/Level set to bone window (W=2000, L=400)")
    print(f"Axial view centered at z={center_z:.1f}")
else:
    print("WARNING: Could not load chest CT volume")

print("Setup complete - ready for Haller Index measurement task")
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
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/pectus_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Pectus Excavatum Haller Index Assessment"
echo "==============================================="
echo ""
echo "You are given a chest CT scan. Measure the Haller Index to assess"
echo "pectus excavatum severity."
echo ""
echo "Steps:"
echo "  1. Navigate to find the level of maximum sternal depression"
echo "     (where sternum is closest to spine, typically T9-T10 level)"
echo "  2. Measure TRANSVERSE diameter (inner rib to inner rib, side-to-side)"
echo "  3. Measure AP diameter (posterior sternum to anterior spine)"
echo "  4. Calculate Haller Index = Transverse / AP"
echo "  5. Classify: Normal(<2.5), Mild(2.5-3.2), Moderate(3.2-3.5), Severe(>3.5)"
echo "  6. Surgical candidate if HI > 3.25"
echo ""
echo "Save outputs to:"
echo "  ~/Documents/SlicerData/LIDC/transverse_measurement.mrk.json"
echo "  ~/Documents/SlicerData/LIDC/ap_measurement.mrk.json"
echo "  ~/Documents/SlicerData/LIDC/haller_index_report.json"
echo ""