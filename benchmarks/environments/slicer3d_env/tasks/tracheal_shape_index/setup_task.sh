#!/bin/bash
echo "=== Setting up Tracheal Shape Index Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0003"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous task outputs
rm -f "$LIDC_DIR/trachea_measurements.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/trachea_report.json" 2>/dev/null || true
rm -f /tmp/trachea_task_result.json 2>/dev/null || true

# Prepare LIDC data
echo "Preparing LIDC-IDRI data..."
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Check if data already exists, otherwise prepare it
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || true

# Get the actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
echo "Using patient: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/trachea_patient_id

# Verify DICOM files exist
DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "WARNING: Only $DICOM_COUNT DICOM files found. Attempting re-download..."
    /workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || true
    DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
fi

echo "Found $DICOM_COUNT DICOM files"

# Generate ground truth tracheal measurements
echo "Computing ground truth tracheal measurements..."
export PATIENT_ID DICOM_DIR GROUND_TRUTH_DIR

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
try:
    import pydicom
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pydicom"])
    import pydicom

try:
    from scipy.ndimage import label as scipy_label
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import label as scipy_label

patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0003")
dicom_dir = os.environ.get("DICOM_DIR", f"/home/ga/Documents/SlicerData/LIDC/{patient_id}/DICOM")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

os.makedirs(gt_dir, exist_ok=True)

def load_dicom_series(folder):
    """Load DICOM series and return volume with spacing."""
    dcm_files = []
    for root, dirs, files in os.walk(folder):
        for f in files:
            fpath = os.path.join(root, f)
            try:
                ds = pydicom.dcmread(fpath, force=True)
                if hasattr(ds, 'pixel_array'):
                    dcm_files.append((fpath, ds))
            except:
                continue
    
    if not dcm_files:
        return None, None, None
    
    def sort_key(item):
        ds = item[1]
        if hasattr(ds, 'SliceLocation') and ds.SliceLocation is not None:
            return float(ds.SliceLocation)
        if hasattr(ds, 'InstanceNumber') and ds.InstanceNumber is not None:
            return int(ds.InstanceNumber)
        return 0
    
    dcm_files.sort(key=sort_key)
    
    slices = []
    for _, ds in dcm_files:
        arr = ds.pixel_array.astype(np.float32)
        slope = float(getattr(ds, 'RescaleSlope', 1))
        intercept = float(getattr(ds, 'RescaleIntercept', 0))
        arr = arr * slope + intercept
        slices.append(arr)
    
    volume = np.stack(slices, axis=0)
    
    ds0 = dcm_files[0][1]
    pixel_spacing = list(ds0.PixelSpacing) if hasattr(ds0, 'PixelSpacing') else [1.0, 1.0]
    slice_thickness = float(ds0.SliceThickness) if hasattr(ds0, 'SliceThickness') else 1.0
    spacing = (slice_thickness, float(pixel_spacing[0]), float(pixel_spacing[1]))
    
    return volume, spacing, len(dcm_files)

print(f"Loading DICOM from {dicom_dir}...")
volume, spacing, n_slices = load_dicom_series(dicom_dir)

if volume is None:
    print("ERROR: Could not load DICOM series")
    # Create default ground truth
    gt_data = {
        "patient_id": patient_id,
        "error": "Could not load DICOM",
        "ap_diameter_mm": 18.0,
        "transverse_diameter_mm": 16.0,
        "tracheal_index": 0.89,
        "classification": "Normal",
        "aortic_arch_slice": 50,
        "measurement_tolerances": {
            "diameter_tolerance_mm": 3.0,
            "slice_tolerance": 2
        }
    }
    gt_path = os.path.join(gt_dir, f"{patient_id}_trachea_gt.json")
    with open(gt_path, 'w') as f:
        json.dump(gt_data, f, indent=2)
    sys.exit(0)

print(f"Volume shape: {volume.shape}, spacing: {spacing}")

nz, ny, nx = volume.shape
center_x = nx // 2
center_y = ny // 2

# Find aortic arch level - look for high-density pixels in mediastinum
x_start = int(nx * 0.35)
x_end = int(nx * 0.65)
y_start = int(ny * 0.3)
y_end = int(ny * 0.7)

aorta_counts = []
for z in range(nz):
    mediastinum = volume[z, y_start:y_end, x_start:x_end]
    aorta_pixels = np.sum((mediastinum > 100) & (mediastinum < 400))
    aorta_counts.append(aorta_pixels)

# Aortic arch typically in upper third
upper_range_start = max(0, nz // 3 - 20)
upper_range_end = min(nz, nz // 3 + 30)
search_range = range(upper_range_start, upper_range_end)
if len(list(search_range)) == 0:
    search_range = range(nz // 4, nz // 2)

arch_slice = max(search_range, key=lambda z: aorta_counts[z])
print(f"Identified aortic arch level at slice {arch_slice}")

# Find trachea at arch level
trachea_slice = volume[arch_slice, :, :]
air_mask = trachea_slice < -900

labeled, n_features = scipy_label(air_mask)

# Find trachea component
trachea_label = None
trachea_centroid = None
best_score = -1

for i in range(1, n_features + 1):
    component = (labeled == i)
    area = np.sum(component)
    area_mm2 = area * spacing[1] * spacing[2]
    
    # Trachea typically 100-600 mm²
    if area_mm2 < 50 or area_mm2 > 800:
        continue
    
    coords = np.argwhere(component)
    cy, cx = coords.mean(axis=0)
    
    # Trachea should be central, slightly posterior
    dist_from_center = np.sqrt((cx - center_x)**2 + (cy - center_y * 0.7)**2)
    score = -dist_from_center + (1.0 / (1 + abs(area_mm2 - 300) / 100))
    
    if score > best_score:
        best_score = score
        trachea_label = i
        trachea_centroid = (cy, cx)

if trachea_label is None:
    print("WARNING: Could not identify trachea, using defaults")
    ap_diameter = 18.0
    trans_diameter = 16.0
else:
    trachea_mask = (labeled == trachea_label)
    coords = np.argwhere(trachea_mask)
    
    y_coords = coords[:, 0]
    x_coords = coords[:, 1]
    
    ap_pixels = y_coords.max() - y_coords.min()
    ap_diameter = float(ap_pixels * spacing[1])
    
    trans_pixels = x_coords.max() - x_coords.min()
    trans_diameter = float(trans_pixels * spacing[2])

tracheal_index = trans_diameter / ap_diameter if ap_diameter > 0 else 1.0

# Classification
if tracheal_index < 0.67:
    classification = "Saber-sheath trachea"
elif tracheal_index <= 1.0:
    classification = "Normal"
else:
    classification = "AP narrowing"

print(f"Ground truth measurements:")
print(f"  AP diameter: {ap_diameter:.1f} mm")
print(f"  Transverse diameter: {trans_diameter:.1f} mm")
print(f"  Tracheal Index: {tracheal_index:.3f}")
print(f"  Classification: {classification}")

gt_data = {
    "patient_id": patient_id,
    "aortic_arch_slice": int(arch_slice),
    "total_slices": int(nz),
    "ap_diameter_mm": round(ap_diameter, 1),
    "transverse_diameter_mm": round(trans_diameter, 1),
    "tracheal_index": round(tracheal_index, 3),
    "classification": classification,
    "spacing_mm": [round(s, 3) for s in spacing],
    "trachea_centroid_yx": [round(c, 1) for c in trachea_centroid] if trachea_centroid else None,
    "measurement_tolerances": {
        "diameter_tolerance_mm": 3.0,
        "slice_tolerance": 2,
        "ti_tolerance": 0.1
    }
}

gt_path = os.path.join(gt_dir, f"{patient_id}_trachea_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF

# Create Slicer Python script to load DICOM
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os
from DICOMLib import DICOMUtils

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading chest CT for patient: {patient_id}")

# Initialize DICOM database
db_dir = '/home/ga/.local/share/NA-MIC/Slicer/DICOM'
if not os.path.exists(db_dir):
    os.makedirs(db_dir)

dicomBrowser = slicer.modules.dicom.widgetRepresentation().self()
dicomBrowser.browserWidget.dicomBrowser.setDatabaseDirectory(db_dir)

# Import DICOM folder
print(f"Importing DICOM from {dicom_dir}...")
DICOMUtils.importDicom(dicom_dir, slicer.dicomDatabase)

# Load patient study
patientUIDs = slicer.dicomDatabase.patients()
if patientUIDs:
    print(f"Found {len(patientUIDs)} patient(s)")
    DICOMUtils.loadPatientByUID(patientUIDs[0])
else:
    print("WARNING: No patients found in DICOM database")

# Get the loaded volume
volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volumeNodes:
    volumeNode = volumeNodes[0]
    volumeNode.SetName("ChestCT")
    
    # Set appropriate lung/mediastinum window for trachea visualization
    displayNode = volumeNode.GetDisplayNode()
    if displayNode:
        # Mediastinum window: W=400, L=40
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volumeNode.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    print(f"CT loaded: {volumeNode.GetName()}")
    print(f"Dimensions: {volumeNode.GetImageData().GetDimensions()}")
else:
    print("WARNING: No volume loaded")

print("Setup complete - ready for tracheal assessment")
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
    
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for data to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/trachea_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tracheal Shape Index Assessment"
echo "======================================="
echo ""
echo "A chest CT scan is loaded. Assess tracheal shape for COPD evaluation."
echo ""
echo "Your goal:"
echo "  1. Navigate to find the aortic arch level (horseshoe-shaped vessel)"
echo "  2. Identify the trachea at this level (dark oval, air-filled)"
echo "  3. Measure AP diameter (front-to-back) in mm"
echo "  4. Measure transverse diameter (side-to-side) in mm"
echo "  5. Calculate Tracheal Index = Transverse / AP"
echo "  6. Classify: Normal (0.67-1.0), Saber-sheath (<0.67), AP narrowing (>1.0)"
echo ""
echo "Save outputs:"
echo "  - Measurements: ~/Documents/SlicerData/LIDC/trachea_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/trachea_report.json"
echo ""