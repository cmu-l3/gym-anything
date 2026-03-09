#!/bin/bash
echo "=== Setting up Caudate-RL Ratio Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="5"

# Ensure directories exist
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga "$IRCADB_DIR" 2>/dev/null || true

# Prepare IRCADb data
echo "Preparing IRCADb liver CT data..."
export PATIENT_NUM GROUND_TRUTH_DIR IRCADB_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi
echo "$PATIENT_NUM" > /tmp/task_patient_num.txt

PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
echo "Using IRCADb patient: $PATIENT_NUM"

# Verify data exists
if [ ! -d "$PATIENT_DIR" ]; then
    echo "ERROR: Patient data not found at $PATIENT_DIR"
    exit 1
fi

# Clean up any previous task outputs
rm -f "$IRCADB_DIR/caudate_measurement.mrk.json" 2>/dev/null || true
rm -f "$IRCADB_DIR/rightlobe_measurement.mrk.json" 2>/dev/null || true
rm -f "$IRCADB_DIR/crl_ratio_report.json" 2>/dev/null || true
rm -f /tmp/crl_task_result.json 2>/dev/null || true

# Compute ground truth C/RL measurements
echo "Computing ground truth C/RL measurements..."
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

from scipy import ndimage

patient_num = os.environ.get("PATIENT_NUM", "5")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
seg_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")

if not os.path.exists(seg_path):
    print(f"Ground truth segmentation not found: {seg_path}")
    # Create a default ground truth for testing
    gt_measurements = {
        "patient_num": patient_num,
        "bifurcation_slice": 50,
        "bifurcation_z_mm": 125.0,
        "caudate_width_mm": 35.0,
        "rightlobe_width_mm": 120.0,
        "crl_ratio": 0.29,
        "classification": "Normal",
        "tolerance_caudate_mm": 8.0,
        "tolerance_rightlobe_mm": 15.0,
        "tolerance_slice_mm": 20.0
    }
    gt_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_crl_gt.json")
    os.makedirs(gt_dir, exist_ok=True)
    with open(gt_path, "w") as f:
        json.dump(gt_measurements, f, indent=2)
    print(f"Created default ground truth at {gt_path}")
    sys.exit(0)

# Load segmentation
print(f"Loading segmentation: {seg_path}")
seg = nib.load(seg_path)
data = seg.get_fdata().astype(np.int16)
spacing = seg.header.get_zooms()[:3]

print(f"Segmentation shape: {data.shape}, spacing: {spacing}")

# Labels: 1=liver, 2=tumor, 3=portal_vein
liver_mask = (data == 1) | (data == 2)
portal_mask = (data == 3)

# Find portal vein bifurcation level (largest cross-section)
portal_slices = []
for z in range(data.shape[2]):
    portal_area = np.sum(portal_mask[:, :, z])
    if portal_area > 0:
        portal_slices.append((z, portal_area))

if portal_slices:
    portal_slices.sort(key=lambda x: x[1], reverse=True)
    bifurcation_z = portal_slices[0][0]
else:
    liver_z_coords = np.where(np.any(liver_mask, axis=(0, 1)))[0]
    bifurcation_z = int(np.median(liver_z_coords)) if len(liver_z_coords) > 0 else data.shape[2] // 2

print(f"Portal bifurcation level: slice {bifurcation_z}")

# Get liver slice at bifurcation level
liver_slice = liver_mask[:, :, bifurcation_z]

if not np.any(liver_slice):
    print("No liver at bifurcation level, using middle slice")
    liver_z = np.where(np.any(liver_mask, axis=(0, 1)))[0]
    if len(liver_z) > 0:
        bifurcation_z = liver_z[len(liver_z)//2]
        liver_slice = liver_mask[:, :, bifurcation_z]

# Find liver boundaries
liver_cols = np.any(liver_slice, axis=0)
col_indices = np.where(liver_cols)[0]

if len(col_indices) == 0:
    print("Could not determine liver boundaries")
    sys.exit(1)

liver_left = col_indices[0]
liver_right = col_indices[-1]
liver_width_pixels = liver_right - liver_left

# Caudate is typically medial 20-30% of liver
caudate_width_pixels = int(liver_width_pixels * 0.25)
caudate_width_mm = caudate_width_pixels * spacing[0]

# Right lobe is the remainder
rightlobe_width_pixels = liver_width_pixels - caudate_width_pixels
rightlobe_width_mm = rightlobe_width_pixels * spacing[0]

# Calculate ratio
if rightlobe_width_mm > 0:
    crl_ratio = caudate_width_mm / rightlobe_width_mm
else:
    crl_ratio = 0

# Classification
if crl_ratio >= 0.80:
    classification = "Highly suggestive of cirrhosis"
elif crl_ratio >= 0.65:
    classification = "Suggestive of cirrhosis"
else:
    classification = "Normal"

# Save ground truth
gt_measurements = {
    "patient_num": patient_num,
    "bifurcation_slice": int(bifurcation_z),
    "bifurcation_z_mm": float(bifurcation_z * spacing[2]),
    "caudate_width_mm": float(round(caudate_width_mm, 1)),
    "rightlobe_width_mm": float(round(rightlobe_width_mm, 1)),
    "crl_ratio": float(round(crl_ratio, 3)),
    "classification": classification,
    "liver_total_width_mm": float(round(liver_width_pixels * spacing[0], 1)),
    "spacing_mm": [float(s) for s in spacing],
    "tolerance_caudate_mm": 8.0,
    "tolerance_rightlobe_mm": 15.0,
    "tolerance_slice_mm": 20.0
}

gt_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_crl_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_measurements, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  Caudate width: {caudate_width_mm:.1f} mm")
print(f"  Right lobe width: {rightlobe_width_mm:.1f} mm")
print(f"  C/RL ratio: {crl_ratio:.3f}")
print(f"  Classification: {classification}")
PYEOF

# Find the CT volume to load
LOAD_FILE=""

# Check for NIfTI volume first
if [ -f "$PATIENT_DIR/ct_volume.nii.gz" ]; then
    LOAD_FILE="$PATIENT_DIR/ct_volume.nii.gz"
elif [ -f "$IRCADB_DIR/patient_${PATIENT_NUM}.nii.gz" ]; then
    LOAD_FILE="$IRCADB_DIR/patient_${PATIENT_NUM}.nii.gz"
else
    # Find any NIfTI file
    LOAD_FILE=$(find "$PATIENT_DIR" "$IRCADB_DIR" -name "*.nii.gz" -o -name "*.nii" 2>/dev/null | head -1)
fi

# If no NIfTI, check for DICOM
if [ -z "$LOAD_FILE" ] && [ -d "$PATIENT_DIR/PATIENT_DICOM" ]; then
    DICOM_COUNT=$(find "$PATIENT_DIR/PATIENT_DICOM" -type f 2>/dev/null | wc -l)
    if [ "$DICOM_COUNT" -gt 10 ]; then
        LOAD_FILE="$PATIENT_DIR/PATIENT_DICOM"
        echo "Will load DICOM series from: $LOAD_FILE"
    fi
fi

echo "CT data to load: $LOAD_FILE"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer loading script
cat > /tmp/load_ircadb_ct.py << PYEOF
import slicer
import os

load_path = "$LOAD_FILE"
patient_num = "$PATIENT_NUM"

print(f"Loading IRCADb patient {patient_num} CT scan...")

volume_node = None

if os.path.isdir(load_path):
    # DICOM directory
    print(f"Loading DICOM from: {load_path}")
    from DICOMLib import DICOMUtils
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(load_path, db)
        patientUIDs = db.patients()
        if patientUIDs:
            DICOMUtils.loadPatientByUID(patientUIDs[0])
    
    # Get loaded volume
    volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volumes:
        volume_node = volumes[0]
else:
    # NIfTI file
    print(f"Loading NIfTI from: {load_path}")
    volume_node = slicer.util.loadVolume(load_path)

if volume_node:
    volume_node.SetName("LiverCT")
    
    # Set abdominal CT window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceLogic = slicer.app.layoutManager().sliceWidget(color).sliceLogic()
        sliceLogic.GetSliceCompositeNode().SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on liver region (approximately mid-volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded: {volume_node.GetImageData().GetDimensions()}")
    print("Window/Level set for abdominal soft tissue (W=350, L=40)")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for C/RL ratio measurement task")
PYEOF

# Launch Slicer
echo "Launching 3D Slicer with liver CT..."
if [ -n "$LOAD_FILE" ]; then
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_ircadb_ct.py > /tmp/slicer_launch.log 2>&1 &
else
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
fi

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

sleep 5

# Take initial screenshot
take_screenshot /tmp/crl_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Caudate-to-Right-Lobe Ratio for Cirrhosis Assessment"
echo "============================================================"
echo ""
echo "Patient: IRCADb #$PATIENT_NUM"
echo ""
echo "Instructions:"
echo "  1. Navigate to the portal vein bifurcation level (axial view)"
echo "  2. Measure the caudate lobe width (between IVC and portal vein)"
echo "  3. Measure the right lobe width at the same level"
echo "  4. Calculate C/RL ratio and classify"
echo ""
echo "Classification:"
echo "  - Normal: C/RL < 0.65"
echo "  - Suggestive of cirrhosis: C/RL 0.65-0.79"
echo "  - Highly suggestive: C/RL >= 0.80"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/IRCADb/caudate_measurement.mrk.json"
echo "  - ~/Documents/SlicerData/IRCADb/rightlobe_measurement.mrk.json"
echo "  - ~/Documents/SlicerData/IRCADb/crl_ratio_report.json"
echo ""