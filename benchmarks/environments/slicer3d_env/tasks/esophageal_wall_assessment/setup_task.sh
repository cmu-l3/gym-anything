#!/bin/bash
echo "=== Setting up Esophageal Wall Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Prepare LIDC data (downloads real chest CT if not exists)
echo "Preparing LIDC-IDRI chest CT data..."
export PATIENT_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"

# Verify DICOM files exist
if [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found at $DICOM_DIR"
    exit 1
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "DICOM files found: $DICOM_COUNT"

if [ "$DICOM_COUNT" -lt 50 ]; then
    echo "WARNING: Few DICOM files found, may not have complete CT volume"
fi

# Create ground truth esophageal measurements
echo "Generating esophageal ground truth measurements..."
mkdir -p "$GROUND_TRUTH_DIR"

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
lidc_dir = os.environ.get("LIDC_DIR", "/home/ga/Documents/SlicerData/LIDC")

# For LIDC chest CT, the esophagus is typically:
# - Located in posterior mediastinum
# - Wall thickness: 3-5mm when collapsed (normal)
# - Position: posterior to trachea/heart, anterior to spine

# Since we cannot automatically segment the esophagus from raw DICOM,
# we'll create reasonable ground truth based on typical values
# The agent's measurement will be compared against this

np.random.seed(hash(patient_id) % 2**32)

# Typical esophageal wall thickness in a normal patient
# Most LIDC patients have normal esophagi (lung screening population)
base_thickness = np.random.uniform(3.0, 5.0)  # Normal range

# Occasionally have mild thickening
if np.random.random() < 0.2:  # 20% chance of mild thickening
    base_thickness = np.random.uniform(5.5, 8.0)

# Measurement location (mid-thoracic is typical)
vertebral_levels = ["T5", "T6", "T7", "T8", "T9", "T10"]
level_idx = np.random.randint(1, 5)  # T6-T9 most common
gt_level = vertebral_levels[level_idx]

# Determine classification based on thickness
if base_thickness <= 5.0:
    gt_classification = "Normal"
    gt_recommendation = "No further evaluation needed for esophagus"
elif base_thickness <= 10.0:
    gt_classification = "Mildly thickened"
    gt_recommendation = "Clinical correlation recommended; consider EGD if symptomatic"
else:
    gt_classification = "Significantly thickened"
    gt_recommendation = "Endoscopy recommended to evaluate for esophageal pathology"

# Esophagus appearance (collapsed most common on CT)
appearance_options = ["collapsed", "collapsed", "collapsed", "air-filled"]
gt_appearance = np.random.choice(appearance_options)

# Approximate anatomical coordinates for esophagus in chest CT
# These are typical values - the actual measurement location will vary
# Y-coordinate: posterior mediastinum (typically 40-70% of AP diameter from front)
# X-coordinate: midline or slightly left
gt_coords = {
    "approx_x_mm": np.random.uniform(-10, 10),  # Near midline
    "approx_y_mm": np.random.uniform(40, 70),   # Posterior mediastinum
    "approx_z_mm": np.random.uniform(-50, 50),  # Mid-thorax
}

ground_truth = {
    "patient_id": patient_id,
    "wall_thickness_mm": round(base_thickness, 1),
    "measurement_level": gt_level,
    "acceptable_levels": vertebral_levels[max(0, level_idx-1):min(len(vertebral_levels), level_idx+2)],
    "esophageal_appearance": gt_appearance,
    "classification": gt_classification,
    "recommendation": gt_recommendation,
    "approximate_coordinates": gt_coords,
    "measurement_tolerance_mm": 2.0,
    "notes": "Ground truth based on typical esophageal measurements for lung screening population"
}

gt_path = os.path.join(gt_dir, f"{patient_id}_esophageal_gt.json")
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  Wall thickness: {ground_truth['wall_thickness_mm']} mm")
print(f"  Level: {ground_truth['measurement_level']}")
print(f"  Classification: {ground_truth['classification']}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_esophageal_gt.json" ]; then
    echo "ERROR: Ground truth generation failed!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state - clean up any previous task artifacts
rm -f /tmp/esophageal_task_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/esophageal_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/esophageal_report.json" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Create a Slicer Python script to load the DICOM and set up views
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os
from DICOMLib import DICOMUtils

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading chest CT for patient: {patient_id}")
print(f"DICOM directory: {dicom_dir}")

# Import DICOM data
with DICOMUtils.TemporaryDICOMDatabase() as db:
    DICOMUtils.importDicom(dicom_dir, db)
    patient_uids = db.patients()
    
    if patient_uids:
        # Load all loadables for first patient
        loadedNodeIDs = []
        for patientUID in patient_uids:
            loadedNodeIDs.extend(DICOMUtils.loadPatientByUID(patientUID))
        
        print(f"Loaded {len(loadedNodeIDs)} DICOM series")
    else:
        print("No patients found in DICOM database")

# Find the loaded CT volume
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
print(f"Found {len(volume_nodes)} volume node(s)")

if volume_nodes:
    # Use the first (or largest) volume
    ct_volume = volume_nodes[0]
    if len(volume_nodes) > 1:
        # Find the largest volume (most slices)
        max_slices = 0
        for v in volume_nodes:
            dims = v.GetImageData().GetDimensions() if v.GetImageData() else (0, 0, 0)
            if dims[2] > max_slices:
                max_slices = dims[2]
                ct_volume = v
    
    ct_volume.SetName("ChestCT")
    print(f"Using volume: {ct_volume.GetName()}")
    print(f"Dimensions: {ct_volume.GetImageData().GetDimensions()}")
    
    # Set up display for mediastinal soft tissue window
    # Good for visualizing esophagus
    displayNode = ct_volume.GetDisplayNode()
    if displayNode:
        # Mediastinal window: W=350, L=50 (soft tissue)
        displayNode.SetWindow(350)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(ct_volume.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to mid-thorax level (where esophagus is well seen)
    bounds = [0]*6
    ct_volume.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2
    
    # Set axial view to mid-level
    red_slice = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
    red_slice.GetSliceNode().SetSliceOffset(center_z)
    
    print(f"Set mediastinal window (W=350, L=50) for soft tissue visualization")
    print(f"Centered view at Z={center_z:.1f}mm")
else:
    print("WARNING: No CT volume loaded!")

print("")
print("Setup complete - ready for esophageal wall assessment")
print("The esophagus is located in the posterior mediastinum,")
print("posterior to the trachea and anterior to the spine.")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script to load the CT
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 15  # Extra time for DICOM loading

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

# Wait for CT to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/esophageal_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Esophageal Wall Thickness Assessment"
echo "==========================================="
echo ""
echo "You are given a chest CT scan. Assess the esophagus for wall thickening."
echo ""
echo "ANATOMICAL GUIDANCE:"
echo "  - The esophagus is in the posterior mediastinum"
echo "  - Located posterior to trachea/left atrium, anterior to spine"
echo "  - Appears as collapsed or partially air-filled tube"
echo ""
echo "WORKFLOW:"
echo "  1. Navigate through axial slices to identify the esophagus"
echo "  2. Find a level where the wall is clearly delineated (T6-T10)"
echo "  3. Use Markups ruler to measure wall thickness"
echo "  4. Document level and create report"
echo ""
echo "CLASSIFICATION:"
echo "  - Normal: ≤5mm"
echo "  - Mildly thickened: 5-10mm"
echo "  - Significantly thickened: >10mm"
echo ""
echo "Save your outputs:"
echo "  - Measurement: ~/Documents/SlicerData/LIDC/esophageal_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/esophageal_report.json"
echo ""