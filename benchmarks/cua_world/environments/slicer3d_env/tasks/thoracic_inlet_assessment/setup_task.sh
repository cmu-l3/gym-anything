#!/bin/bash
echo "=== Setting up Thoracic Inlet Assessment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare LIDC data (downloads real data if not exists)
echo "Preparing LIDC-IDRI chest CT data..."
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || {
    echo "LIDC data preparation had issues, continuing..."
}

# Get the actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"
echo "DICOM directory: $DICOM_DIR"

# Check if DICOM data exists
if [ ! -d "$DICOM_DIR" ] || [ "$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)" -lt 10 ]; then
    echo "WARNING: DICOM data may be incomplete. Checking..."
    find "$LIDC_DIR" -name "*.dcm" -o -name "*.DCM" 2>/dev/null | head -5
fi

# Pre-compute ground truth thoracic inlet measurements
echo "Computing ground truth measurements..."
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

patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")
lidc_dir = os.environ.get("LIDC_DIR", "/home/ga/Documents/SlicerData/LIDC")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

dicom_dir = os.path.join(lidc_dir, patient_id, "DICOM")

print(f"Loading DICOM from: {dicom_dir}")

# Find all DICOM files
dcm_files = []
for root, dirs, files in os.walk(dicom_dir):
    for f in files:
        fpath = os.path.join(root, f)
        try:
            ds = pydicom.dcmread(fpath, force=True)
            if hasattr(ds, 'pixel_array') and hasattr(ds, 'ImagePositionPatient'):
                dcm_files.append(ds)
        except Exception:
            continue

if not dcm_files:
    print("ERROR: No valid DICOM files found")
    # Create default ground truth for fallback
    gt_data = {
        "patient_id": patient_id,
        "t1_slice_index": 50,
        "t1_z_position_mm": 0.0,
        "ap_diameter_mm": 47.0,
        "transverse_diameter_mm": 115.0,
        "thoracic_inlet_index": 0.41,
        "classification": "Normal",
        "cervical_rib_present": False,
        "tolerance_level_mm": 10,
        "tolerance_ap_mm": 5,
        "tolerance_trans_mm": 8,
        "error": "DICOM loading failed - using default values"
    }
    os.makedirs(gt_dir, exist_ok=True)
    gt_path = os.path.join(gt_dir, f"{patient_id}_thoracic_inlet_gt.json")
    with open(gt_path, 'w') as f:
        json.dump(gt_data, f, indent=2)
    print(f"Default ground truth saved to {gt_path}")
    sys.exit(0)

print(f"Loaded {len(dcm_files)} DICOM slices")

# Sort by slice location
dcm_files.sort(key=lambda x: float(x.ImagePositionPatient[2]) if hasattr(x, 'ImagePositionPatient') else 0)

# Get volume parameters
pixel_spacing = [float(x) for x in dcm_files[0].PixelSpacing] if hasattr(dcm_files[0], 'PixelSpacing') else [1.0, 1.0]
slice_thickness = float(dcm_files[0].SliceThickness) if hasattr(dcm_files[0], 'SliceThickness') else 2.5

# Build volume
slices = [ds.pixel_array for ds in dcm_files]
volume = np.stack(slices, axis=2)
z_positions = [float(ds.ImagePositionPatient[2]) for ds in dcm_files]

print(f"Volume shape: {volume.shape}")
print(f"Pixel spacing: {pixel_spacing}, Slice thickness: {slice_thickness}")

# Use HU thresholding to find bone
# Apply rescale if available
rescale_slope = float(dcm_files[0].RescaleSlope) if hasattr(dcm_files[0], 'RescaleSlope') else 1.0
rescale_intercept = float(dcm_files[0].RescaleIntercept) if hasattr(dcm_files[0], 'RescaleIntercept') else 0.0

volume_hu = volume * rescale_slope + rescale_intercept
bone_mask = volume_hu > 200  # Cortical bone threshold

# Find approximate T1 level
# T1 is where sternum (manubrium) begins anteriorly and first ribs are visible
# Search from superior (high Z) to inferior

found_t1_slice = None
midline = volume.shape[1] // 2

for z_idx in range(volume.shape[2] - 1, max(0, volume.shape[2] // 2), -1):
    axial_slice = volume_hu[:, :, z_idx]
    bone_slice = bone_mask[:, :, z_idx]
    
    # Check for sternum (anterior midline bone)
    anterior_region = axial_slice[:volume.shape[0]//3, midline-30:midline+30]
    
    # Look for bone in anterior midline
    if np.any(anterior_region > 250):
        # Check for lateral bone (ribs)
        left_region = bone_slice[:, :volume.shape[1]//4]
        right_region = bone_slice[:, 3*volume.shape[1]//4:]
        
        if np.sum(left_region) > 300 and np.sum(right_region) > 300:
            found_t1_slice = z_idx
            break

if found_t1_slice is None:
    # Fallback: estimate T1 at ~75% from top of scan (thoracic inlet is superior)
    found_t1_slice = int(volume.shape[2] * 0.75)
    print(f"T1 not detected, using fallback slice: {found_t1_slice}")

t1_z = z_positions[found_t1_slice] if found_t1_slice < len(z_positions) else 0.0
print(f"T1 level estimated at slice {found_t1_slice}, Z={t1_z:.1f}mm")

# Measure at T1 level
axial_t1 = volume_hu[:, :, found_t1_slice]
bone_t1 = bone_mask[:, :, found_t1_slice]

# Find AP diameter: distance from anterior bone to posterior bone at midline
midline_profile = bone_t1[:, midline]
bone_indices = np.where(midline_profile)[0]

if len(bone_indices) > 1:
    ap_diameter_pixels = bone_indices[-1] - bone_indices[0]
    ap_diameter_mm = ap_diameter_pixels * pixel_spacing[0]
else:
    ap_diameter_mm = 47.0  # Default if measurement fails

# Find transverse diameter
center_row = volume.shape[0] // 2
trans_profile = bone_t1[center_row, :]
bone_trans = np.where(trans_profile)[0]

if len(bone_trans) > 1:
    left_bone = bone_trans[bone_trans < midline]
    right_bone = bone_trans[bone_trans > midline]
    
    if len(left_bone) > 0 and len(right_bone) > 0:
        trans_diameter_pixels = right_bone[0] - left_bone[-1]
        trans_diameter_mm = trans_diameter_pixels * pixel_spacing[1]
    else:
        trans_diameter_mm = 115.0
else:
    trans_diameter_mm = 115.0

# Ensure reasonable values
ap_diameter_mm = max(30.0, min(70.0, ap_diameter_mm))
trans_diameter_mm = max(80.0, min(150.0, trans_diameter_mm))

# Calculate index
ti_index = ap_diameter_mm / trans_diameter_mm if trans_diameter_mm > 0 else 0.41

# Classification
if ti_index < 0.40 or ap_diameter_mm < 35 or trans_diameter_mm < 90:
    classification = "Narrowed"
elif ti_index > 0.60:
    classification = "Wide"
else:
    classification = "Normal"

# Check for cervical rib (simplified)
cervical_rib_present = False
if found_t1_slice + 5 < volume.shape[2]:
    upper_slice = bone_mask[:, :, min(found_t1_slice + 10, volume.shape[2]-1)]
    lateral_bone = np.sum(upper_slice[:, :volume.shape[1]//4]) + np.sum(upper_slice[:, 3*volume.shape[1]//4:])
    if lateral_bone > 1500:
        cervical_rib_present = True

# Save ground truth
gt_data = {
    "patient_id": patient_id,
    "t1_slice_index": int(found_t1_slice),
    "t1_z_position_mm": float(t1_z),
    "ap_diameter_mm": float(round(ap_diameter_mm, 1)),
    "transverse_diameter_mm": float(round(trans_diameter_mm, 1)),
    "thoracic_inlet_index": float(round(ti_index, 3)),
    "classification": classification,
    "cervical_rib_present": cervical_rib_present,
    "pixel_spacing_mm": pixel_spacing,
    "slice_thickness_mm": slice_thickness,
    "tolerance_level_mm": 10,
    "tolerance_ap_mm": 5,
    "tolerance_trans_mm": 8,
    "volume_shape": list(volume.shape)
}

os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{patient_id}_thoracic_inlet_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"AP diameter: {ap_diameter_mm:.1f}mm")
print(f"Transverse diameter: {trans_diameter_mm:.1f}mm")
print(f"Index: {ti_index:.3f}")
print(f"Classification: {classification}")
print(f"Cervical rib: {cervical_rib_present}")
PYEOF

# Export environment variables for Python
export PATIENT_ID LIDC_DIR GROUND_TRUTH_DIR

# Clean any existing agent output
rm -f "$LIDC_DIR/thoracic_inlet_ap.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/thoracic_inlet_trans.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/thoracic_inlet_report.json" 2>/dev/null || true

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Start Slicer
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
wait_for_slicer 90

# Focus and maximize window
sleep 5
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
fi

# Save DICOM path for agent reference
echo "$DICOM_DIR" > /tmp/dicom_path.txt

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Thoracic Inlet Assessment Task Setup Complete ==="
echo ""
echo "TASK: Thoracic Inlet Dimensional Assessment"
echo "============================================="
echo ""
echo "DICOM data location: $DICOM_DIR"
echo ""
echo "Instructions:"
echo "  1. Import DICOM from: $DICOM_DIR"
echo "     (Use File > Add DICOM Data or DICOM module)"
echo "  2. Navigate to T1 vertebral level (first thoracic vertebra)"
echo "  3. Measure AP diameter (posterior manubrium to anterior T1)"
echo "  4. Measure transverse diameter (between first ribs)"
echo "  5. Calculate index and classify findings"
echo ""
echo "Save outputs to:"
echo "  - AP measurement: $LIDC_DIR/thoracic_inlet_ap.mrk.json"
echo "  - Trans measurement: $LIDC_DIR/thoracic_inlet_trans.mrk.json"
echo "  - Report: $LIDC_DIR/thoracic_inlet_report.json"
echo ""