#!/bin/bash
echo "=== Setting up Bone Density HU Screening Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="${LIDC_PATIENT_ID:-LIDC-IDRI-0001}"

# Ensure directories exist
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare LIDC data
echo "Preparing LIDC chest CT data..."
bash /workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Find the actual patient directory
PATIENT_DIR=""
for dir in "$LIDC_DIR"/*; do
    if [ -d "$dir/DICOM" ]; then
        PATIENT_DIR="$dir"
        PATIENT_ID=$(basename "$dir")
        break
    fi
done

if [ -z "$PATIENT_DIR" ] || [ ! -d "$PATIENT_DIR/DICOM" ]; then
    echo "ERROR: LIDC DICOM data not found"
    exit 1
fi

DICOM_DIR="$PATIENT_DIR/DICOM"
DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)

if [ "$DICOM_COUNT" -lt 50 ]; then
    echo "ERROR: Insufficient DICOM files ($DICOM_COUNT < 50)"
    exit 1
fi

echo "Found $DICOM_COUNT DICOM files for $PATIENT_ID"

# Calculate ground truth bone density values
echo "Computing ground truth vertebral HU values..."

python3 << PYEOF
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

patient_id = "$PATIENT_ID"
dicom_dir = "$DICOM_DIR"
gt_dir = "$GROUND_TRUTH_DIR"

print(f"Loading DICOM from {dicom_dir}...")

# Load DICOM series
dcm_files = []
for root, dirs, files in os.walk(dicom_dir):
    for f in files:
        fpath = os.path.join(root, f)
        try:
            ds = pydicom.dcmread(fpath, force=True)
            if hasattr(ds, 'pixel_array') and hasattr(ds, 'ImagePositionPatient'):
                dcm_files.append((fpath, ds))
        except Exception:
            continue

if len(dcm_files) < 50:
    print(f"WARNING: Only {len(dcm_files)} valid DICOM slices found")
    # Create minimal ground truth
    gt = {
        "patient_id": patient_id,
        "error": "insufficient_slices",
        "t12": {"trabecular_hu": 150, "classification": "Osteopenia"},
        "l1": None,
        "tolerance_hu": 25
    }
    os.makedirs(gt_dir, exist_ok=True)
    with open(os.path.join(gt_dir, f"{patient_id}_bone_density_gt.json"), 'w') as f:
        json.dump(gt, f, indent=2)
    sys.exit(0)

# Sort by slice location
def get_slice_location(item):
    ds = item[1]
    if hasattr(ds, 'SliceLocation'):
        return float(ds.SliceLocation)
    elif hasattr(ds, 'ImagePositionPatient'):
        return float(ds.ImagePositionPatient[2])
    return 0

dcm_files.sort(key=get_slice_location)

# Build volume
slices = []
for _, ds in dcm_files:
    arr = ds.pixel_array.astype(np.float32)
    slope = float(getattr(ds, 'RescaleSlope', 1))
    intercept = float(getattr(ds, 'RescaleIntercept', 0))
    arr = arr * slope + intercept
    slices.append(arr)

volume = np.stack(slices, axis=2)
print(f"Volume shape: {volume.shape}")

# Get spacing
ds0 = dcm_files[0][1]
pixel_spacing = [float(x) for x in getattr(ds0, 'PixelSpacing', [1.0, 1.0])]
slice_thickness = float(getattr(ds0, 'SliceThickness', 2.5))
spacing = (pixel_spacing[0], pixel_spacing[1], slice_thickness)
print(f"Spacing: {spacing}")

# Find spine region (bone in posterior half)
rows, cols, slices_n = volume.shape
posterior_start = int(rows * 0.5)

# Look for vertebral bodies
bone_mask = (volume > 150) & (volume < 1500)
bone_mask[:posterior_start, :, :] = False

# Find spine center
if np.any(bone_mask):
    coords = np.argwhere(bone_mask)
    spine_center_row = int(np.median(coords[:, 0]))
    spine_center_col = int(np.median(coords[:, 1]))
else:
    spine_center_row = int(rows * 0.7)
    spine_center_col = cols // 2

print(f"Spine center: row={spine_center_row}, col={spine_center_col}")

# Sample vertebral bodies along z-axis
vertebral_measurements = []
window_size = 25

for z in range(15, volume.shape[2] - 15, 3):
    r_start = max(0, spine_center_row - window_size)
    r_end = min(rows, spine_center_row + window_size)
    c_start = max(0, spine_center_col - window_size)
    c_end = min(cols, spine_center_col + window_size)
    
    region = volume[r_start:r_end, c_start:c_end, z]
    center_r = region.shape[0] // 2
    center_c = region.shape[1] // 2
    
    # Central ROI for trabecular bone
    roi_size = 8
    central_roi = region[max(0,center_r-roi_size):center_r+roi_size, 
                         max(0,center_c-roi_size):center_c+roi_size]
    
    if central_roi.size > 0:
        # Filter for trabecular bone HU range
        trabecular_vals = central_roi[(central_roi > 30) & (central_roi < 400)]
        if len(trabecular_vals) > 20:
            mean_hu = float(np.mean(trabecular_vals))
            std_hu = float(np.std(trabecular_vals))
            if 50 < mean_hu < 350 and std_hu < 120:
                vertebral_measurements.append({
                    'slice': z,
                    'z_mm': float(z * spacing[2]),
                    'mean_hu': mean_hu,
                    'std_hu': std_hu,
                    'row': spine_center_row,
                    'col': spine_center_col
                })

print(f"Found {len(vertebral_measurements)} vertebral body samples")

# Estimate T12/L1 locations (lower 20-35% of chest CT)
total_z = volume.shape[2] * spacing[2]

t12_target_z = total_z * 0.25
l1_target_z = total_z * 0.18

t12_data = None
l1_data = None
min_dist_t12 = float('inf')
min_dist_l1 = float('inf')

for vb in vertebral_measurements:
    dist_t12 = abs(vb['z_mm'] - t12_target_z)
    dist_l1 = abs(vb['z_mm'] - l1_target_z)
    
    if dist_t12 < min_dist_t12:
        min_dist_t12 = dist_t12
        t12_data = vb.copy()
    
    if dist_l1 < min_dist_l1 and vb != t12_data:
        min_dist_l1 = dist_l1
        l1_data = vb.copy()

# Classification function
def classify_bone_density(hu_value):
    if hu_value > 160:
        return "Normal"
    elif hu_value >= 110:
        return "Osteopenia"
    else:
        return "Osteoporosis"

# Build ground truth
ground_truth = {
    "patient_id": patient_id,
    "volume_shape": list(volume.shape),
    "spacing_mm": list(spacing),
    "spine_center": {"row": spine_center_row, "col": spine_center_col},
    "tolerance_hu": 25,
    "t12": None,
    "l1": None
}

if t12_data:
    ground_truth["t12"] = {
        "slice_index": t12_data['slice'],
        "z_mm": t12_data['z_mm'],
        "trabecular_hu": t12_data['mean_hu'],
        "trabecular_std": t12_data['std_hu'],
        "classification": classify_bone_density(t12_data['mean_hu'])
    }
    print(f"T12: HU={t12_data['mean_hu']:.1f}, Classification={ground_truth['t12']['classification']}")

if l1_data:
    ground_truth["l1"] = {
        "slice_index": l1_data['slice'],
        "z_mm": l1_data['z_mm'],
        "trabecular_hu": l1_data['mean_hu'],
        "trabecular_std": l1_data['std_hu'],
        "classification": classify_bone_density(l1_data['mean_hu'])
    }
    print(f"L1: HU={l1_data['mean_hu']:.1f}, Classification={ground_truth['l1']['classification']}")

# Save ground truth
os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{patient_id}_bone_density_gt.json")
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF

# Save patient ID for later
echo "$PATIENT_ID" > /tmp/bone_density_patient_id.txt

# Clean up any previous outputs
rm -f "$LIDC_DIR/bone_density_roi.seg.nrrd" 2>/dev/null || true
rm -f "$LIDC_DIR/bone_density_roi.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/bone_density_report.json" 2>/dev/null || true

# Record initial file count for anti-gaming
ls "$LIDC_DIR"/*.nrrd "$LIDC_DIR"/*.json 2>/dev/null | wc -l > /tmp/initial_file_count.txt || echo "0" > /tmp/initial_file_count.txt

# Close any existing Slicer instances
pkill -f Slicer 2>/dev/null || true
sleep 2

# Create Slicer loading script
cat > /tmp/load_lidc_ct.py << 'LOADEOF'
import slicer
import os
import glob

dicom_dir = os.environ.get('DICOM_DIR', '')
patient_id = os.environ.get('PATIENT_ID', 'LIDC')

print(f"Loading DICOM from: {dicom_dir}")

try:
    # Import DICOM using DICOMLib
    from DICOMLib import DICOMUtils
    
    # Import the DICOM folder to the database
    dicomBrowser = slicer.modules.dicom.widgetRepresentation().self()
    
    # Try to load directly
    loadedNodeIDs = DICOMUtils.loadDICOMFromFolder(dicom_dir)
    
    if loadedNodeIDs:
        print(f"Loaded {len(loadedNodeIDs)} nodes from DICOM")
    else:
        # Fallback: try loading first DICOM file as volume
        dcm_files = []
        for root, dirs, files in os.walk(dicom_dir):
            for f in files:
                dcm_files.append(os.path.join(root, f))
        if dcm_files:
            slicer.util.loadVolume(dcm_files[0])
            print(f"Loaded volume from {dcm_files[0]}")

except Exception as e:
    print(f"DICOM import error: {e}")
    # Ultimate fallback
    import glob
    dcm_files = glob.glob(os.path.join(dicom_dir, "**/*"), recursive=True)
    dcm_files = [f for f in dcm_files if os.path.isfile(f)]
    if dcm_files:
        try:
            slicer.util.loadVolume(dcm_files[0])
        except:
            pass

# Configure display for bone visualization
volumeNode = slicer.mrmlScene.GetFirstNodeByClass("vtkMRMLScalarVolumeNode")
if volumeNode:
    volumeNode.SetName("ChestCT")
    displayNode = volumeNode.GetDisplayNode()
    if displayNode:
        # Bone window: W=1500, L=400
        displayNode.SetWindow(1500)
        displayNode.SetLevel(400)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceLogic = slicer.app.layoutManager().sliceWidget(color).sliceLogic()
        sliceLogic.GetSliceCompositeNode().SetBackgroundVolumeID(volumeNode.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to lower portion (where T12/L1 would be)
    bounds = [0]*6
    volumeNode.GetBounds(bounds)
    z_center = bounds[4] + (bounds[5] - bounds[4]) * 0.25  # Lower 25%
    
    redWidget = slicer.app.layoutManager().sliceWidget("Red")
    redWidget.sliceLogic().GetSliceNode().SetSliceOffset(z_center)
    
    print(f"CT loaded with bone window (W=1500, L=400)")
    print(f"Navigated to lower thoracic region (z={z_center:.1f})")

# Set layout to conventional (axial primary)
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

print("Setup complete - ready for bone density measurement")
LOADEOF

# Launch Slicer with DICOM loading
export DICOM_DIR="$DICOM_DIR"
export PATIENT_ID="$PATIENT_ID"
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 DICOM_DIR="$DICOM_DIR" PATIENT_ID="$PATIENT_ID" /opt/Slicer/Slicer --python-script /tmp/load_lidc_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
fi

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo ""
echo "=== Bone Density HU Screening Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_ID"
echo "Data location: $DICOM_DIR"
echo ""
echo "TASK INSTRUCTIONS:"
echo "=================="
echo "1. Navigate to T12 or L1 vertebral body"
echo "2. Place circular ROI (~150 mm²) in trabecular bone center"
echo "3. Measure mean HU value"
echo "4. Classify: Normal (>160 HU), Osteopenia (110-160 HU), Osteoporosis (<110 HU)"
echo "5. Save ROI to ~/Documents/SlicerData/LIDC/bone_density_roi.seg.nrrd"
echo "6. Save report to ~/Documents/SlicerData/LIDC/bone_density_report.json"
echo ""