#!/bin/bash
echo "=== Setting up Liver Ablation Suitability Assessment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date)"

# Configuration
PATIENT_NUM="${PATIENT_NUM:-5}"
IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Create directories
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare IRCADb data (downloads real data if not exists)
echo "Preparing IRCADb liver CT data (Patient $PATIENT_NUM)..."
export PATIENT_NUM IRCADB_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Save patient number for verification
echo "$PATIENT_NUM" > /tmp/ircadb_patient_num

# Record initial state - clean up any previous outputs
echo "Cleaning previous task outputs..."
rm -f "$IRCADB_DIR/lesion_measurements.mrk.json" 2>/dev/null || true
rm -f "$IRCADB_DIR/ablation_report.json" 2>/dev/null || true
rm -f /tmp/ablation_task_result.json 2>/dev/null || true

# Set permissions
chown -R ga:ga "$IRCADB_DIR" 2>/dev/null || true
chmod -R 755 "$IRCADB_DIR" 2>/dev/null || true

# Find CT volume to load
CT_FILE=""
PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"

# Look for NIfTI volume first
if [ -f "$PATIENT_DIR/ct_volume.nii.gz" ]; then
    CT_FILE="$PATIENT_DIR/ct_volume.nii.gz"
    echo "Found NIfTI CT volume: $CT_FILE"
elif [ -d "$PATIENT_DIR/PATIENT_DICOM" ] && [ "$(ls -A "$PATIENT_DIR/PATIENT_DICOM" 2>/dev/null)" ]; then
    CT_FILE="$PATIENT_DIR/PATIENT_DICOM"
    echo "Found DICOM directory: $CT_FILE"
else
    echo "WARNING: CT data not found in expected locations"
    ls -la "$PATIENT_DIR" 2>/dev/null || echo "Patient directory does not exist"
fi

# Verify ground truth exists
GT_FILE="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json"
if [ -f "$GT_FILE" ]; then
    echo "Ground truth verified: $GT_FILE"
else
    echo "WARNING: Ground truth not found at $GT_FILE"
fi

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load CT and set up appropriate view
cat > /tmp/load_liver_ct.py << 'PYEOF'
import slicer
import os
import sys

patient_dir = os.environ.get("PATIENT_DIR", "/home/ga/Documents/SlicerData/IRCADb/patient_5")
ct_file = os.environ.get("CT_FILE", "")

print(f"Loading liver CT data from: {patient_dir}")

volume_node = None

# Try loading NIfTI first
nifti_path = os.path.join(patient_dir, "ct_volume.nii.gz")
if os.path.exists(nifti_path):
    print(f"Loading NIfTI: {nifti_path}")
    volume_node = slicer.util.loadVolume(nifti_path)
elif ct_file and os.path.exists(ct_file):
    if os.path.isdir(ct_file):
        # Load DICOM directory
        print(f"Loading DICOM directory: {ct_file}")
        from DICOMLib import DICOMUtils
        with DICOMUtils.TemporaryDICOMDatabase() as db:
            DICOMUtils.importDicom(ct_file, db)
            patientUIDs = db.patients()
            if patientUIDs:
                loadedNodeIDs = DICOMUtils.loadPatientByUID(patientUIDs[0])
                if loadedNodeIDs:
                    volume_node = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])
    else:
        print(f"Loading file: {ct_file}")
        volume_node = slicer.util.loadVolume(ct_file)

if volume_node:
    volume_node.SetName("LiverCT")
    
    # Set abdominal CT window/level for liver viewing
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Liver window: W=150, L=30-60 (good for soft tissue/liver)
        displayNode.SetWindow(200)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to approximate liver region (center of volume, slightly right)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded successfully")
    print(f"  Dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"  Window/Level set for liver viewing (W=200, L=50)")
else:
    print("WARNING: Could not load CT volume")
    print("Please load the CT data manually from:")
    print(f"  {patient_dir}")

print("")
print("=== TASK: Liver Lesion Ablation Suitability Assessment ===")
print("Evaluate the hepatic lesion for thermal ablation eligibility.")
PYEOF

# Set environment variables for Python script
export PATIENT_DIR="$PATIENT_DIR"
export CT_FILE="$CT_FILE"

# Launch Slicer with the loading script
echo "Launching 3D Slicer with liver CT..."
sudo -u ga DISPLAY=:1 PATIENT_DIR="$PATIENT_DIR" CT_FILE="$CT_FILE" /opt/Slicer/Slicer --python-script /tmp/load_liver_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120
sleep 15

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for data to load
sleep 5

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/ablation_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Liver Lesion Ablation Suitability Assessment"
echo "==================================================="
echo ""
echo "You are evaluating a hepatic lesion for thermal ablation."
echo ""
echo "Your objectives:"
echo "  1. Locate the hepatic lesion in the liver"
echo "  2. Measure lesion dimensions (length × width × height in mm)"
echo "  3. Measure distance to hepatic vein (mm)"
echo "  4. Measure distance to portal vein (mm)"
echo "  5. Measure distance to liver capsule (mm)"
echo "  6. Identify Couinaud liver segment (I-VIII)"
echo "  7. Classify: 'ideal', 'feasible', or 'not_suitable'"
echo "  8. If feasible/ideal, mark proposed entry point"
echo ""
echo "Ablation Criteria:"
echo "  - IDEAL: ≤30mm, ≥10mm from vessels/capsule"
echo "  - FEASIBLE: 30-50mm OR 5-10mm from vessels/capsule"
echo "  - NOT_SUITABLE: >50mm OR <5mm from major vessel"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/IRCADb/lesion_measurements.mrk.json"
echo "  - ~/Documents/SlicerData/IRCADb/ablation_report.json"
echo ""