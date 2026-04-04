#!/bin/bash
echo "=== Setting up Window/Level Optimization Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Ensure directories exist
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Remove any previous outputs
rm -f "$LIDC_DIR/lung_window.png" 2>/dev/null || true
rm -f "$LIDC_DIR/soft_tissue_window.png" 2>/dev/null || true
rm -f "$LIDC_DIR/bone_window.png" 2>/dev/null || true
rm -f "$LIDC_DIR/window_level_report.json" 2>/dev/null || true

# Prepare LIDC data (downloads real chest CT if not exists)
echo "Preparing LIDC chest CT data..."
/workspace/scripts/prepare_lidc_data.sh "LIDC-IDRI-0001" || {
    echo "WARNING: LIDC data preparation failed, using fallback..."
}

# Check if LIDC data exists, otherwise use sample CT data or create synthetic
PATIENT_ID="LIDC-IDRI-0001"
CT_FILE=""

# Look for DICOM directory first
if [ -d "$LIDC_DIR/$PATIENT_ID/DICOM" ] && [ "$(ls -1 "$LIDC_DIR/$PATIENT_ID/DICOM/" 2>/dev/null | wc -l)" -gt 10 ]; then
    echo "Found LIDC DICOM data"
    CT_FILE="$LIDC_DIR/$PATIENT_ID/DICOM"
    USE_DICOM="true"
# Check for NIfTI format
elif [ -f "$LIDC_DIR/${PATIENT_ID}.nii.gz" ]; then
    echo "Found LIDC NIfTI data"
    CT_FILE="$LIDC_DIR/${PATIENT_ID}.nii.gz"
    USE_DICOM="false"
# Use sample chest CT if available
elif [ -f "/home/ga/Documents/SlicerData/SampleData/CTChest.nrrd" ]; then
    echo "Using sample CTChest data"
    CT_FILE="/home/ga/Documents/SlicerData/SampleData/CTChest.nrrd"
    USE_DICOM="false"
# Generate synthetic chest CT as last resort
else
    echo "Generating synthetic chest CT data..."
    python3 << 'PYEOF'
import numpy as np
import os

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

# Create synthetic chest CT with realistic HU values
np.random.seed(42)
nx, ny, nz = 256, 256, 150
spacing = (0.7, 0.7, 2.5)  # mm

# Create volume
ct_data = np.full((nx, ny, nz), -1000, dtype=np.int16)  # Air background

# Create body contour (ellipse)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (70**2)) <= 1.0

# Fill body with soft tissue
for z in range(nz):
    ct_data[:, :, z][body_mask] = np.random.normal(40, 10, np.sum(body_mask)).astype(np.int16)

# Create lungs (air-filled, left and right)
lung_l_cx, lung_l_cy = center_x + 35, center_y - 10
lung_r_cx, lung_r_cy = center_x - 35, center_y - 10

for z in range(int(nz*0.2), int(nz*0.85)):
    # Left lung
    lung_l_mask = ((X - lung_l_cx)**2 / (30**2) + (Y - lung_l_cy)**2 / (40**2)) <= 1.0
    ct_data[:, :, z][lung_l_mask & body_mask] = np.random.normal(-850, 50, np.sum(lung_l_mask & body_mask)).astype(np.int16)
    
    # Right lung
    lung_r_mask = ((X - lung_r_cx)**2 / (30**2) + (Y - lung_r_cy)**2 / (40**2)) <= 1.0
    ct_data[:, :, z][lung_r_mask & body_mask] = np.random.normal(-850, 50, np.sum(lung_r_mask & body_mask)).astype(np.int16)

# Create spine (bone density)
spine_cx, spine_cy = center_x, center_y + 50
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 15**2
    ct_data[:, :, z][spine_mask] = np.random.normal(500, 100, np.sum(spine_mask)).astype(np.int16)

# Create ribs (bilateral arcs)
for z in range(int(nz*0.25), int(nz*0.8), 8):
    for side in [-1, 1]:
        rib_cx = center_x + side * 60
        rib_cy = center_y + 30
        rib_mask = (((X - rib_cx)**2 + (Y - rib_cy)**2) <= 10**2) & (((X - rib_cx)**2 + (Y - rib_cy)**2) >= 5**2)
        rib_mask = rib_mask & body_mask
        ct_data[:, :, z][rib_mask] = np.random.normal(600, 80, np.sum(rib_mask)).astype(np.int16)

# Create sternum
sternum_cx, sternum_cy = center_x, center_y - 55
for z in range(int(nz*0.3), int(nz*0.7)):
    sternum_mask = ((X - sternum_cx)**2 / (8**2) + (Y - sternum_cy)**2 / (3**2)) <= 1.0
    sternum_mask = sternum_mask & body_mask
    ct_data[:, :, z][sternum_mask] = np.random.normal(550, 70, np.sum(sternum_mask)).astype(np.int16)

# Create heart/mediastinum (soft tissue density)
heart_cx, heart_cy = center_x + 10, center_y
for z in range(int(nz*0.35), int(nz*0.65)):
    heart_mask = ((X - heart_cx)**2 / (25**2) + (Y - heart_cy)**2 / (30**2)) <= 1.0
    ct_data[:, :, z][heart_mask & body_mask] = np.random.normal(45, 12, np.sum(heart_mask & body_mask)).astype(np.int16)

# Create aorta (slightly brighter than heart)
aorta_cx, aorta_cy = center_x - 5, center_y + 25
for z in range(int(nz*0.2), int(nz*0.9)):
    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= 12**2
    ct_data[:, :, z][aorta_mask & body_mask] = np.random.normal(55, 10, np.sum(aorta_mask & body_mask)).astype(np.int16)

# Save as NIfTI
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

nii = nib.Nifti1Image(ct_data, affine)
output_path = os.path.join(output_dir, "LIDC-IDRI-0001.nii.gz")
nib.save(nii, output_path)
print(f"Synthetic chest CT saved to {output_path}")
print(f"Shape: {ct_data.shape}, spacing: {spacing}")
PYEOF
    CT_FILE="$LIDC_DIR/LIDC-IDRI-0001.nii.gz"
    USE_DICOM="false"
fi

echo "CT file: $CT_FILE"
echo "Using DICOM: ${USE_DICOM:-false}"

# Save CT file path for export script
echo "$CT_FILE" > /tmp/lidc_ct_path.txt
echo "${USE_DICOM:-false}" > /tmp/lidc_use_dicom.txt

# Create Slicer Python script to load the CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
use_dicom = "${USE_DICOM:-false}" == "true"

print(f"Loading chest CT from: {ct_path}")
print(f"Use DICOM: {use_dicom}")

volume_node = None

if use_dicom and os.path.isdir(ct_path):
    # Load DICOM directory
    from DICOMLib import DICOMUtils
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(ct_path, db)
        patient_uids = db.patients()
        if patient_uids:
            loadable_uids = db.seriesForPatient(patient_uids[0])
            if loadable_uids:
                volume_node = DICOMUtils.loadSeriesByUID(loadable_uids)
else:
    # Load NIfTI or NRRD
    volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    print(f"Loaded volume: {volume_node.GetName()}")
    print(f"Dimensions: {volume_node.GetImageData().GetDimensions()}")
    
    # Set initial window/level to a neutral starting point
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Start with soft tissue window (agent needs to change it)
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Center on data
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print("Chest CT loaded - ready for window/level adjustment")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the loading script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for agent
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/wl_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Window/Level Optimization for Multi-Tissue Visualization"
echo "==============================================================="
echo ""
echo "You have a chest CT scan loaded. Apply THREE different window/level"
echo "presets and save a screenshot for each:"
echo ""
echo "1. LUNG WINDOW (Width ~1500, Level ~-500)"
echo "   - Visualize lung parenchyma detail"
echo "   - Save: ~/Documents/SlicerData/LIDC/lung_window.png"
echo ""
echo "2. SOFT TISSUE WINDOW (Width ~400, Level ~40)"
echo "   - Visualize mediastinal structures"
echo "   - Save: ~/Documents/SlicerData/LIDC/soft_tissue_window.png"
echo ""
echo "3. BONE WINDOW (Width ~2000, Level ~400)"
echo "   - Visualize ribs and vertebrae"
echo "   - Save: ~/Documents/SlicerData/LIDC/bone_window.png"
echo ""
echo "4. Create report: ~/Documents/SlicerData/LIDC/window_level_report.json"
echo "   Format: {\"lung_window\": {\"width\": X, \"level\": Y}, ...}"
echo ""