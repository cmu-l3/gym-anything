#!/bin/bash
echo "=== Setting up Tracheal Carina Localization Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean previous task state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/carina_fiducials.json 2>/dev/null || true
echo "0" > /tmp/initial_fiducial_count.txt

# ============================================================
# Prepare LIDC chest CT data
# ============================================================
echo "Preparing LIDC-IDRI chest CT data..."
export PATIENT_ID GROUND_TRUTH_DIR LIDC_DIR

# Run data preparation script
bash /workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" 2>&1 || {
    echo "WARNING: LIDC data preparation had issues, continuing..."
}

# Get the actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

echo "Using patient: $PATIENT_ID"

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

# Verify DICOM exists
if [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found at $DICOM_DIR"
    # Try alternate locations
    DICOM_DIR=$(find "$LIDC_DIR" -type d -name "DICOM" 2>/dev/null | head -1)
    if [ -z "$DICOM_DIR" ]; then
        echo "ERROR: Could not find any DICOM directory"
        exit 1
    fi
    echo "Found DICOM at: $DICOM_DIR"
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "Found $DICOM_COUNT DICOM files"

if [ "$DICOM_COUNT" -lt 50 ]; then
    echo "ERROR: Too few DICOM files ($DICOM_COUNT), data may be incomplete"
    exit 1
fi

# ============================================================
# Compute ground truth carina location
# ============================================================
echo "Computing ground truth carina location..."

python3 << 'PYEOF'
import os
import sys
import json
import glob
import numpy as np

# Ensure dependencies
try:
    import pydicom
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pydicom"])
    import pydicom

try:
    from scipy.ndimage import binary_opening, label as scipy_label, center_of_mass
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import binary_opening, label as scipy_label, center_of_mass

dicom_dir = os.environ.get("DICOM_DIR", "/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0001/DICOM")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

print(f"Loading DICOM from {dicom_dir}...")

# Load DICOM series
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
    # Create fallback ground truth
    fallback_gt = {
        "patient_id": patient_id,
        "carina_ras": [0, -50, -150],
        "bounds_min_ras": [-20, -70, -180],
        "bounds_max_ras": [20, -30, -120],
        "error": "No DICOM data - using fallback"
    }
    with open(os.path.join(gt_dir, "carina_location.json"), 'w') as f:
        json.dump(fallback_gt, f, indent=2)
    sys.exit(0)

print(f"Found {len(dcm_files)} DICOM files with pixel data")

# Sort by slice position
def get_z(item):
    ds = item[1]
    if hasattr(ds, 'ImagePositionPatient'):
        return float(ds.ImagePositionPatient[2])
    if hasattr(ds, 'SliceLocation'):
        return float(ds.SliceLocation)
    if hasattr(ds, 'InstanceNumber'):
        return float(ds.InstanceNumber)
    return 0

dcm_files.sort(key=get_z)

# Build volume
slices = [ds.pixel_array.astype(np.int16) for _, ds in dcm_files]
volume = np.stack(slices, axis=2)
print(f"Volume shape: {volume.shape}")

# Get spacing and origin
ds0 = dcm_files[0][1]
pixel_spacing = [1.0, 1.0]
if hasattr(ds0, 'PixelSpacing'):
    pixel_spacing = [float(ds0.PixelSpacing[0]), float(ds0.PixelSpacing[1])]

slice_thickness = 1.0
if hasattr(ds0, 'SliceThickness'):
    slice_thickness = float(ds0.SliceThickness)
elif len(dcm_files) > 1:
    z0 = get_z(dcm_files[0])
    z1 = get_z(dcm_files[1])
    slice_thickness = abs(z1 - z0) if abs(z1 - z0) > 0 else 1.0

spacing = [pixel_spacing[0], pixel_spacing[1], slice_thickness]

origin = [0, 0, 0]
if hasattr(ds0, 'ImagePositionPatient'):
    origin = [float(x) for x in ds0.ImagePositionPatient]

print(f"Spacing: {spacing} mm, Origin: {origin}")

# Convert to HU
rescale_slope = float(ds0.RescaleSlope) if hasattr(ds0, 'RescaleSlope') else 1.0
rescale_intercept = float(ds0.RescaleIntercept) if hasattr(ds0, 'RescaleIntercept') else 0.0
volume_hu = volume * rescale_slope + rescale_intercept

print(f"HU range: {volume_hu.min()} to {volume_hu.max()}")

# Segment airway (air: HU < -900)
airway_mask = (volume_hu < -850) & (volume_hu > -1024)

# Clean up with morphological operations
try:
    airway_mask = binary_opening(airway_mask, iterations=2)
except Exception as e:
    print(f"Warning: morphological opening failed: {e}")

# Find connected components
labeled, num_features = scipy_label(airway_mask)
print(f"Found {num_features} connected air components")

if num_features == 0:
    print("WARNING: No airway components found, using geometric estimate")
    # Estimate carina at center of volume, upper-middle region
    carina_ijk = [volume.shape[0] / 2, volume.shape[1] / 2, volume.shape[2] * 0.6]
else:
    # Find trachea (largest component in upper portion)
    upper_third_z = int(volume.shape[2] * 2 / 3)
    component_sizes_upper = []
    for i in range(1, min(num_features + 1, 50)):  # Limit search
        mask_i = (labeled == i)
        upper_count = np.sum(mask_i[:, :, upper_third_z:])
        total_count = np.sum(mask_i)
        if total_count > 100:  # Minimum size
            component_sizes_upper.append((i, upper_count, total_count))

    if not component_sizes_upper:
        print("WARNING: No significant airway components, using center estimate")
        carina_ijk = [volume.shape[0] / 2, volume.shape[1] / 2, volume.shape[2] * 0.55]
    else:
        # Sort by presence in upper volume (trachea should be prominent superiorly)
        component_sizes_upper.sort(key=lambda x: x[1], reverse=True)
        trachea_label = component_sizes_upper[0][0]
        trachea_mask = (labeled == trachea_label)
        print(f"Trachea component: label {trachea_label}, {np.sum(trachea_mask)} voxels")

        # Find carina by detecting bifurcation
        # Look for slice where airway splits from 1 to 2 components
        carina_z = None
        prev_components = 1

        for z in range(volume.shape[2] - 1, -1, -1):  # Inferior to superior
            slice_mask = trachea_mask[:, :, z]
            if np.sum(slice_mask) < 10:
                continue
            
            slice_labeled, slice_components = scipy_label(slice_mask)
            
            # Detect transition from 2+ components to 1 (going superior)
            if slice_components == 1 and prev_components >= 2:
                carina_z = z
                print(f"Bifurcation detected at z={z}")
                break
            
            prev_components = slice_components

        if carina_z is None:
            # Fallback: use centroid in lower portion of trachea
            z_coords = np.where(np.any(trachea_mask, axis=(0, 1)))[0]
            if len(z_coords) > 0:
                carina_z = int(z_coords[int(len(z_coords) * 0.3)])  # Lower third
            else:
                carina_z = int(volume.shape[2] * 0.5)
            print(f"Fallback carina z: {carina_z}")

        # Get centroid at carina slice
        carina_slice = trachea_mask[:, :, carina_z]
        if np.sum(carina_slice) > 0:
            com = center_of_mass(carina_slice)
            carina_ijk = [com[0], com[1], carina_z]
        else:
            overall_com = center_of_mass(trachea_mask)
            carina_ijk = [overall_com[0], overall_com[1], carina_z]

# Convert IJK to RAS coordinates
carina_ras = [
    float(origin[0] + carina_ijk[0] * spacing[0]),
    float(origin[1] + carina_ijk[1] * spacing[1]),
    float(origin[2] + carina_ijk[2] * spacing[2])
]

print(f"Carina IJK: {carina_ijk}")
print(f"Carina RAS: {carina_ras}")

# Define acceptable bounds
tolerance_xy = 15.0
tolerance_z = 20.0

gt_data = {
    "patient_id": patient_id,
    "carina_ras": carina_ras,
    "carina_ijk": [float(x) for x in carina_ijk],
    "tolerance_xy_mm": tolerance_xy,
    "tolerance_z_mm": tolerance_z,
    "volume_shape": list(volume.shape),
    "spacing_mm": spacing,
    "origin_ras": [float(x) for x in origin],
    "bounds_min_ras": [
        carina_ras[0] - tolerance_xy,
        carina_ras[1] - tolerance_xy,
        carina_ras[2] - tolerance_z
    ],
    "bounds_max_ras": [
        carina_ras[0] + tolerance_xy,
        carina_ras[1] + tolerance_xy,
        carina_ras[2] + tolerance_z
    ]
}

gt_path = os.path.join(gt_dir, "carina_location.json")
os.makedirs(gt_dir, exist_ok=True)
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"Expected carina RAS: {carina_ras}")
print(f"Acceptable bounds: {gt_data['bounds_min_ras']} to {gt_data['bounds_max_ras']}")
PYEOF

# Export environment variables for Python script
export DICOM_DIR GROUND_TRUTH_DIR PATIENT_ID

# Set permissions for ground truth
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true
chown -R root:root "$GROUND_TRUTH_DIR" 2>/dev/null || true

# ============================================================
# Launch 3D Slicer with DICOM data
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer
pkill -f Slicer 2>/dev/null || true
sleep 2

# Create a Python script to load DICOM
LOAD_SCRIPT="/tmp/load_lidc_dicom.py"
cat > "$LOAD_SCRIPT" << PYEOF
import slicer
import os

dicom_dir = "$DICOM_DIR"
print(f"Loading DICOM from: {dicom_dir}")

try:
    # Initialize DICOM database
    db_path = os.path.join(slicer.app.temporaryPath, "SlicerDICOMDatabase")
    dicomBrowser = slicer.modules.dicom.widgetRepresentation().self()
    
    if not slicer.dicomDatabase.isOpen:
        slicer.dicomDatabase.openDatabase(db_path)
    
    # Import DICOM files
    from DICOMLib import DICOMUtils
    DICOMUtils.importDicom(dicom_dir)
    
    # Load the first series
    patient_uids = slicer.dicomDatabase.patients()
    if patient_uids:
        for patient_uid in patient_uids:
            studies = slicer.dicomDatabase.studiesForPatient(patient_uid)
            if studies:
                for study in studies:
                    series_list = slicer.dicomDatabase.seriesForStudy(study)
                    if series_list:
                        # Load the series with most files (main CT)
                        best_series = None
                        max_files = 0
                        for series in series_list:
                            files = slicer.dicomDatabase.filesForSeries(series)
                            if len(files) > max_files:
                                max_files = len(files)
                                best_series = series
                        
                        if best_series:
                            DICOMUtils.loadSeriesByUID([best_series])
                            print(f"Loaded series with {max_files} files")
                            break
                break
    
    print("DICOM loading complete")
except Exception as e:
    print(f"Error loading DICOM: {e}")
    # Fallback: try direct file loading
    import glob
    dcm_files = glob.glob(os.path.join(dicom_dir, "**/*"), recursive=True)
    dcm_files = [f for f in dcm_files if os.path.isfile(f)]
    if dcm_files:
        print(f"Attempting direct load of {len(dcm_files)} files...")
        slicer.util.loadVolume(dcm_files[0])
PYEOF

chmod 644 "$LOAD_SCRIPT"
chown ga:ga "$LOAD_SCRIPT"

# Launch Slicer
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$LOAD_SCRIPT" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
wait_for_slicer 90

# Give time for DICOM to load
echo "Waiting for DICOM data to load..."
sleep 15

# Maximize and focus window
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Patient: $PATIENT_ID"
echo "DICOM location: $DICOM_DIR"
echo ""
echo "TASK: Navigate through the chest CT to locate the tracheal carina"
echo "      (where the trachea splits into left and right bronchi)"
echo "      and place a fiducial marker named 'Carina' at that location."
echo ""
echo "Hints:"
echo "  - The trachea appears as a dark circle in axial view"
echo "  - Scroll inferiorly to find where it bifurcates"
echo "  - Use coronal view to see the inverted-V shape"
echo "  - Use Markups > Point to create the fiducial"