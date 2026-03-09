#!/bin/bash
echo "=== Setting up Cardiothoracic Ratio Measurement Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Prepare LIDC data (downloads real data if not exists)
echo "Preparing LIDC-IDRI chest CT data..."
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

export PATIENT_ID GROUND_TRUTH_DIR LIDC_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"

# Verify DICOM directory exists and has files
if [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found at $DICOM_DIR"
    exit 1
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files ($DICOM_COUNT) - data may not have downloaded"
    exit 1
fi
echo "DICOM directory found with $DICOM_COUNT files"

# Record initial state
rm -f /tmp/ctr_task_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/cardiac_diameter.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/thoracic_diameter.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/ctr_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt

# Compute reference CTR measurements from CT data for verification
echo "Computing reference measurements from CT data..."
python3 << PYEOF
import os
import sys
import json
import glob

# Try to import pydicom
try:
    import pydicom
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pydicom"])
    import pydicom

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

dicom_dir = "$DICOM_DIR"
gt_dir = "$GROUND_TRUTH_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading DICOM series from {dicom_dir}...")

# Find all DICOM files
dcm_files = []
for root, dirs, files in os.walk(dicom_dir):
    for f in files:
        fpath = os.path.join(root, f)
        try:
            ds = pydicom.dcmread(fpath, force=True)
            if hasattr(ds, 'pixel_array'):
                dcm_files.append((fpath, ds))
        except Exception:
            continue

if not dcm_files:
    print("ERROR: No valid DICOM files found")
    sys.exit(1)

print(f"Found {len(dcm_files)} DICOM files with pixel data")

# Sort by instance number or slice location
def get_sort_key(item):
    ds = item[1]
    if hasattr(ds, 'InstanceNumber') and ds.InstanceNumber is not None:
        return int(ds.InstanceNumber)
    if hasattr(ds, 'SliceLocation') and ds.SliceLocation is not None:
        return float(ds.SliceLocation)
    return 0

dcm_files.sort(key=get_sort_key)

# Get pixel spacing
ds0 = dcm_files[0][1]
pixel_spacing = [1.0, 1.0]
if hasattr(ds0, 'PixelSpacing'):
    pixel_spacing = [float(ds0.PixelSpacing[0]), float(ds0.PixelSpacing[1])]

print(f"Pixel spacing: {pixel_spacing} mm")

# Load volume
slices = []
for fpath, ds in dcm_files:
    slices.append(ds.pixel_array)

volume = np.stack(slices, axis=-1)
print(f"Volume shape: {volume.shape}")

# Find heart region using intensity thresholding
# Heart (with contrast) appears brighter than lung, darker than bone
# Typical HU: lung -900 to -500, heart (soft tissue) 20-80, bone > 300

# Find the slice with maximum cardiac cross-section
# Estimate by looking for the slice where soft tissue area is largest in central region

best_slice = -1
max_cardiac_area = 0
estimated_cardiac_diameter = 0
estimated_thoracic_diameter = 0

for z in range(volume.shape[2]):
    slice_data = volume[:, :, z]
    
    # Normalize to HU-like values (assuming typical CT window)
    if hasattr(ds0, 'RescaleIntercept') and hasattr(ds0, 'RescaleSlope'):
        slice_hu = slice_data * float(ds0.RescaleSlope) + float(ds0.RescaleIntercept)
    else:
        slice_hu = slice_data.astype(float)
    
    # Soft tissue mask (heart region): HU between -50 and 150
    soft_tissue = (slice_hu > -50) & (slice_hu < 150)
    
    # Central region (where heart would be)
    h, w = slice_hu.shape
    cx, cy = w // 2, h // 2
    margin = min(w, h) // 4
    
    central_region = np.zeros_like(soft_tissue)
    central_region[cy-margin:cy+margin, cx-margin:cx+margin] = True
    
    cardiac_region = soft_tissue & central_region
    cardiac_area = np.sum(cardiac_region)
    
    if cardiac_area > max_cardiac_area:
        max_cardiac_area = cardiac_area
        best_slice = z
        
        # Estimate thoracic diameter (air-tissue boundary)
        # Find the leftmost and rightmost lung boundaries
        air_mask = slice_hu < -300
        if np.any(air_mask):
            rows = np.any(air_mask, axis=0)
            if np.any(rows):
                cols_with_air = np.where(rows)[0]
                thoracic_width_pixels = cols_with_air[-1] - cols_with_air[0] if len(cols_with_air) > 1 else 0
                estimated_thoracic_diameter = thoracic_width_pixels * pixel_spacing[0]
        
        # Estimate cardiac diameter from soft tissue in central region
        if np.any(cardiac_region):
            cols = np.any(cardiac_region, axis=0)
            if np.any(cols):
                cols_with_cardiac = np.where(cols)[0]
                cardiac_width_pixels = cols_with_cardiac[-1] - cols_with_cardiac[0] if len(cols_with_cardiac) > 1 else 0
                estimated_cardiac_diameter = cardiac_width_pixels * pixel_spacing[0]

# Calculate expected CTR
if estimated_thoracic_diameter > 0:
    expected_ctr = estimated_cardiac_diameter / estimated_thoracic_diameter
else:
    expected_ctr = 0

# Classification based on expected CTR
if expected_ctr < 0.50:
    expected_classification = "Normal"
elif expected_ctr <= 0.55:
    expected_classification = "Borderline"
else:
    expected_classification = "Cardiomegaly"

# Save ground truth reference
gt_data = {
    "patient_id": patient_id,
    "reference_cardiac_diameter_mm": round(estimated_cardiac_diameter, 1),
    "reference_thoracic_diameter_mm": round(estimated_thoracic_diameter, 1),
    "reference_ctr": round(expected_ctr, 3),
    "reference_slice_index": int(best_slice),
    "expected_classification": expected_classification,
    "pixel_spacing_mm": pixel_spacing,
    "volume_shape": list(volume.shape),
    "tolerance_percent": 15,
    "note": "Reference computed via intensity thresholding - actual measurements may vary"
}

gt_path = os.path.join(gt_dir, f"{patient_id}_ctr_reference.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nReference measurements saved to {gt_path}")
print(f"  Best slice: {best_slice}")
print(f"  Estimated cardiac diameter: {estimated_cardiac_diameter:.1f} mm")
print(f"  Estimated thoracic diameter: {estimated_thoracic_diameter:.1f} mm")
print(f"  Expected CTR: {expected_ctr:.3f}")
print(f"  Classification: {expected_classification}")
PYEOF

# Create a Slicer Python script to load the DICOM data
cat > /tmp/load_lidc_dicom.py << PYEOF
import slicer
import os
from DICOMLib import DICOMUtils

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading LIDC chest CT for {patient_id}...")

# Import DICOM data
print("Importing DICOM files...")
DICOMUtils.importDicom(dicom_dir)

# Load the patient
print("Loading patient data...")
loadedNodeIDs = DICOMUtils.loadPatientByPatientID(patient_id.replace("-", ""))

if not loadedNodeIDs:
    # Try alternative loading approach
    print("Trying alternative loading...")
    dicomBrowser = slicer.modules.dicom.widgetRepresentation().self().browserWidget.dicomBrowser
    dicomBrowser.importDirectory(dicom_dir, dicomBrowser.ImportDirectoryAddLink)
    dicomBrowser.waitForImportFinished()
    
    # Get series and load first one
    db = slicer.dicomDatabase
    patients = db.patients()
    if patients:
        studies = db.studiesForPatient(patients[0])
        if studies:
            series = db.seriesForStudy(studies[0])
            if series:
                loadedNodeIDs = DICOMUtils.loadSeriesByUID([series[0]])

volume_node = None
if loadedNodeIDs:
    for nodeID in loadedNodeIDs:
        node = slicer.mrmlScene.GetNodeByID(nodeID)
        if node and node.IsA("vtkMRMLScalarVolumeNode"):
            volume_node = node
            break

if volume_node:
    volume_node.SetName("ChestCT")
    print(f"Loaded volume: {volume_node.GetName()}")
    
    # Set appropriate lung/mediastinum window
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Mediastinal window - good for seeing heart borders
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to approximate cardiac level
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2
    
    # Set red slice to axial view at center
    red_widget = slicer.app.layoutManager().sliceWidget("Red")
    red_logic = red_widget.sliceLogic()
    red_node = red_logic.GetSliceNode()
    red_node.SetSliceOffset(center_z)
    
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Set initial slice to z={center_z:.1f}")
else:
    print("WARNING: Could not load CT volume from DICOM")

print("Setup complete - ready for CTR measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_lidc_dicom.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 15

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
take_screenshot /tmp/ctr_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Cardiothoracic Ratio (CTR) Measurement"
echo "============================================="
echo ""
echo "You are given a chest CT scan. Measure the cardiothoracic ratio"
echo "to screen for cardiomegaly."
echo ""
echo "Your goal:"
echo "  1. Navigate to the level of maximum cardiac diameter (axial view)"
echo "  2. Measure the maximum TRANSVERSE CARDIAC DIAMETER (horizontal line)"
echo "     - From right heart border to left heart border"
echo "  3. Measure the maximum INTERNAL THORACIC DIAMETER at same level"
echo "     - From inner rib to inner rib"
echo "  4. Calculate CTR = Cardiac Diameter / Thoracic Diameter"
echo "  5. Classify: Normal (<0.50), Borderline (0.50-0.55), Cardiomegaly (>0.55)"
echo ""
echo "Save your outputs:"
echo "  - ~/Documents/SlicerData/LIDC/cardiac_diameter.mrk.json"
echo "  - ~/Documents/SlicerData/LIDC/thoracic_diameter.mrk.json"
echo "  - ~/Documents/SlicerData/LIDC/ctr_report.json"
echo ""