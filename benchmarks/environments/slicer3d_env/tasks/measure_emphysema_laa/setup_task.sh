#!/bin/bash
echo "=== Setting up Emphysema LAA% Measurement Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded"

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Clean any previous task results
rm -f "$EXPORTS_DIR/emphysema_analysis.json" 2>/dev/null || true
rm -f /tmp/emphysema_task_result.json 2>/dev/null || true
rm -f /tmp/emphysema_ground_truth.json 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_segment_count.txt
ls -1 "$EXPORTS_DIR"/*.json 2>/dev/null | wc -l > /tmp/initial_export_count.txt || echo "0" > /tmp/initial_export_count.txt

# ============================================================
# Prepare LIDC data (download real chest CT)
# ============================================================
echo "Preparing LIDC-IDRI chest CT data..."

export PATIENT_ID GROUND_TRUTH_DIR LIDC_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the patient ID actually used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi
echo "$PATIENT_ID" > /tmp/emphysema_patient_id.txt

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
echo "Using patient: $PATIENT_ID"

# Verify DICOM directory
if [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found at $DICOM_DIR"
    exit 1
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files ($DICOM_COUNT)"
    exit 1
fi
echo "Found $DICOM_COUNT DICOM files"

# ============================================================
# Compute ground truth LAA% from CT data
# ============================================================
echo "Computing ground truth LAA% measurements..."

python3 << 'PYEOF'
import os
import sys
import json
import glob

# Ensure dependencies
try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

try:
    import pydicom
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pydicom"])
    import pydicom

dicom_dir = os.environ.get("DICOM_DIR", "/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0001/DICOM")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

print(f"Loading DICOM from: {dicom_dir}")

# Load DICOM files
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
    print("ERROR: No valid DICOM files")
    sys.exit(1)

print(f"Loaded {len(dcm_files)} DICOM slices")

# Sort by instance/location
def get_sort_key(item):
    ds = item[1]
    if hasattr(ds, 'InstanceNumber') and ds.InstanceNumber is not None:
        return int(ds.InstanceNumber)
    if hasattr(ds, 'SliceLocation') and ds.SliceLocation is not None:
        return float(ds.SliceLocation)
    return 0

dcm_files.sort(key=get_sort_key)

# Get spacing info
ds0 = dcm_files[0][1]
pixel_spacing = [1.0, 1.0]
slice_thickness = 1.0

if hasattr(ds0, 'PixelSpacing'):
    pixel_spacing = [float(ds0.PixelSpacing[0]), float(ds0.PixelSpacing[1])]
if hasattr(ds0, 'SliceThickness'):
    slice_thickness = float(ds0.SliceThickness)
elif len(dcm_files) > 1:
    # Estimate from slice positions
    ds1 = dcm_files[1][1]
    if hasattr(ds0, 'SliceLocation') and hasattr(ds1, 'SliceLocation'):
        slice_thickness = abs(float(ds1.SliceLocation) - float(ds0.SliceLocation))

voxel_volume_mm3 = pixel_spacing[0] * pixel_spacing[1] * slice_thickness
voxel_volume_ml = voxel_volume_mm3 / 1000.0

print(f"Pixel spacing: {pixel_spacing}, Slice thickness: {slice_thickness}")
print(f"Voxel volume: {voxel_volume_mm3:.4f} mm³ = {voxel_volume_ml:.6f} mL")

# Build volume and convert to HU
slices = []
for fpath, ds in dcm_files:
    arr = ds.pixel_array.astype(np.float32)
    # Apply rescale
    if hasattr(ds, 'RescaleSlope') and hasattr(ds, 'RescaleIntercept'):
        arr = arr * float(ds.RescaleSlope) + float(ds.RescaleIntercept)
    slices.append(arr)

volume = np.stack(slices, axis=-1)
print(f"Volume shape: {volume.shape}")
print(f"HU range: {volume.min():.1f} to {volume.max():.1f}")

# ============================================================
# Segment lungs using threshold
# Lung parenchyma: typically -950 to -400 HU
# ============================================================
LUNG_MIN_HU = -950
LUNG_MAX_HU = -400
EMPHYSEMA_THRESHOLD_HU = -950

# Create lung mask
lung_mask = (volume >= LUNG_MIN_HU) & (volume <= LUNG_MAX_HU)

# Remove small components and edge artifacts using morphological operations
from scipy.ndimage import binary_erosion, binary_dilation, label as scipy_label

# Clean up lung mask - remove tiny components
labeled_lung, num_components = scipy_label(lung_mask)
component_sizes = [(labeled_lung == i).sum() for i in range(1, num_components + 1)]

if component_sizes:
    # Keep only the two largest components (left and right lungs)
    sorted_indices = np.argsort(component_sizes)[::-1]
    clean_lung_mask = np.zeros_like(lung_mask)
    for i in range(min(2, len(sorted_indices))):
        component_idx = sorted_indices[i] + 1
        clean_lung_mask |= (labeled_lung == component_idx)
    lung_mask = clean_lung_mask

# Calculate total lung volume
total_lung_voxels = np.sum(lung_mask)
total_lung_volume_ml = total_lung_voxels * voxel_volume_ml

print(f"Total lung voxels: {total_lung_voxels}")
print(f"Total lung volume: {total_lung_volume_ml:.1f} mL")

# ============================================================
# Calculate emphysema (LAA below -950 HU within lung)
# ============================================================
emphysema_mask = lung_mask & (volume < EMPHYSEMA_THRESHOLD_HU)
emphysema_voxels = np.sum(emphysema_mask)
emphysema_volume_ml = emphysema_voxels * voxel_volume_ml

# Calculate LAA%
if total_lung_voxels > 0:
    laa_percent = (emphysema_voxels / total_lung_voxels) * 100.0
else:
    laa_percent = 0.0

print(f"Emphysema voxels: {emphysema_voxels}")
print(f"Emphysema volume: {emphysema_volume_ml:.1f} mL")
print(f"LAA%: {laa_percent:.2f}%")

# Classification
if laa_percent < 5:
    classification = "Normal"
elif laa_percent < 15:
    classification = "Mild"
elif laa_percent < 25:
    classification = "Moderate"
else:
    classification = "Severe"

print(f"Classification: {classification} emphysema")

# Save ground truth
gt_data = {
    "patient_id": patient_id,
    "threshold_hu": EMPHYSEMA_THRESHOLD_HU,
    "lung_threshold_range_hu": [LUNG_MIN_HU, LUNG_MAX_HU],
    "total_lung_voxels": int(total_lung_voxels),
    "emphysema_voxels": int(emphysema_voxels),
    "total_lung_volume_ml": float(round(total_lung_volume_ml, 2)),
    "emphysema_volume_ml": float(round(emphysema_volume_ml, 2)),
    "laa_percent": float(round(laa_percent, 2)),
    "classification": classification,
    "voxel_volume_ml": float(voxel_volume_ml),
    "pixel_spacing_mm": pixel_spacing,
    "slice_thickness_mm": float(slice_thickness),
    "volume_shape": list(volume.shape)
}

gt_path = os.path.join(gt_dir, f"{patient_id}_emphysema_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

# Also save to tmp for easier access
with open("/tmp/emphysema_ground_truth.json", "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to: {gt_path}")
print(f"Reference LAA%: {laa_percent:.2f}%")
print(f"Reference lung volume: {total_lung_volume_ml:.1f} mL")
PYEOF

# Set permissions
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true
chown -R ga:ga "$LIDC_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true

# ============================================================
# Launch 3D Slicer with DICOM data
# ============================================================
echo "Launching 3D Slicer with chest CT..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load DICOM and go to Segment Editor
LOAD_SCRIPT="/tmp/load_lidc_for_emphysema.py"
cat > "$LOAD_SCRIPT" << 'PYEOF'
import slicer
import os

# DICOM database setup
dicom_dir = os.environ.get("DICOM_DIR", "/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0001/DICOM")
print(f"Loading DICOM from: {dicom_dir}")

# Import DICOM
from DICOMLib import DICOMUtils
loadedNodeIDs = []

try:
    # Initialize DICOM database if needed
    if not slicer.dicomDatabase or not slicer.dicomDatabase.isOpen:
        db_path = os.path.expanduser("~/.config/NA-MIC/Slicer/ctkDICOM.sql")
        slicer.app.settings().setValue("DatabaseDirectory", os.path.dirname(db_path))
        DICOMUtils.openTemporaryDatabase()
    
    # Import and load
    DICOMUtils.importDicom(dicom_dir)
    patientUIDs = slicer.dicomDatabase.patients()
    if patientUIDs:
        loadedNodeIDs = DICOMUtils.loadPatientByUID(patientUIDs[0])
        print(f"Loaded {len(loadedNodeIDs)} nodes")
except Exception as e:
    print(f"DICOM import error: {e}")
    # Try direct volume loading as fallback
    try:
        import glob
        dcm_files = glob.glob(os.path.join(dicom_dir, "**/*"), recursive=True)
        dcm_files = [f for f in dcm_files if os.path.isfile(f)]
        if dcm_files:
            slicer.util.loadVolume(dcm_files[0])
            print("Loaded via fallback method")
    except Exception as e2:
        print(f"Fallback load error: {e2}")

# Set up views for lung visualization
try:
    # Set lung window/level
    volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volumeNodes:
        volumeNode = volumeNodes[0]
        displayNode = volumeNode.GetDisplayNode()
        if displayNode:
            # Lung window: W=1500, L=-600
            displayNode.SetAutoWindowLevel(False)
            displayNode.SetWindow(1500)
            displayNode.SetLevel(-600)
            print("Set lung window/level")
        
        # Center on volume
        slicer.util.resetSliceViews()
except Exception as e:
    print(f"View setup error: {e}")

print("DICOM loading complete - ready for emphysema analysis")
PYEOF

chmod 644 "$LOAD_SCRIPT"
export DICOM_DIR="$DICOM_DIR"

# Launch Slicer
su - ga -c "DISPLAY=:1 DICOM_DIR='$DICOM_DIR' /opt/Slicer/Slicer --python-script '$LOAD_SCRIPT' > /tmp/slicer_emphysema.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start and load data..."
sleep 15

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Maximize and focus
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/emphysema_initial.png ga 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/emphysema_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_ID"
echo "DICOM files: $DICOM_COUNT"
echo "Output file: $EXPORTS_DIR/emphysema_analysis.json"
echo ""
echo "TASK: Measure LAA% (Low Attenuation Area percentage) for emphysema assessment"
echo ""
echo "Steps:"
echo "  1. Chest CT is loaded - navigate to view lung parenchyma"
echo "  2. Go to Segment Editor module"
echo "  3. Create lung segmentation (threshold -950 to -400 HU for normal lung)"
echo "  4. Identify emphysematous regions (< -950 HU within lungs)"
echo "  5. Use Segment Statistics to calculate volumes"
echo "  6. Calculate LAA% = (Emphysema Volume / Total Lung Volume) × 100"
echo "  7. Save results to: $EXPORTS_DIR/emphysema_analysis.json"
echo ""