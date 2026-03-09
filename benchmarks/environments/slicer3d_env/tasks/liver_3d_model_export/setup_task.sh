#!/bin/bash
echo "=== Setting up Liver 3D Model Export Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="5"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date -Iseconds)"

# Prepare IRCADb data (downloads real data if not exists)
echo "Preparing IRCADb data..."
export PATIENT_NUM GROUND_TRUTH_DIR IRCADB_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get the patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"

echo "Using patient: $PATIENT_NUM"

# Clean up any previous task outputs to ensure fresh start
echo "Cleaning up previous outputs..."
rm -f "$IRCADB_DIR/liver_model.stl" 2>/dev/null || true
rm -f "$IRCADB_DIR/tumor_model.stl" 2>/dev/null || true
rm -f "$IRCADB_DIR/model_report.json" 2>/dev/null || true
rm -f "$IRCADB_DIR"/*.mrml 2>/dev/null || true
rm -f /tmp/liver_task_result.json 2>/dev/null || true

# Verify CT data exists
CT_FILE=""
if [ -f "$IRCADB_DIR/ct_volume.nii.gz" ]; then
    CT_FILE="$IRCADB_DIR/ct_volume.nii.gz"
    echo "Found NIfTI CT volume: $CT_FILE"
elif [ -d "$PATIENT_DIR/PATIENT_DICOM" ]; then
    CT_FILE="$PATIENT_DIR/PATIENT_DICOM"
    echo "Found DICOM directory: $CT_FILE"
else
    echo "ERROR: No CT data found for patient $PATIENT_NUM"
    exit 1
fi

# Verify ground truth exists
GT_FILE="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth not found at $GT_FILE"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "patient_num": "$PATIENT_NUM",
    "ct_source": "$CT_FILE",
    "liver_stl_exists": false,
    "tumor_stl_exists": false,
    "report_exists": false
}
EOF

# Create a Slicer Python script to load the CT with proper window/level
cat > /tmp/load_ircadb_ct.py << 'PYEOF'
import slicer
import os
import glob

patient_num = os.environ.get("PATIENT_NUM", "5")
ircadb_dir = os.environ.get("IRCADB_DIR", "/home/ga/Documents/SlicerData/IRCADb")
patient_dir = os.path.join(ircadb_dir, f"patient_{patient_num}")

print(f"Loading IRCADb patient {patient_num} CT scan...")

volume_node = None

# Try NIfTI first
nifti_path = os.path.join(ircadb_dir, "ct_volume.nii.gz")
if os.path.exists(nifti_path):
    print(f"Loading NIfTI: {nifti_path}")
    volume_node = slicer.util.loadVolume(nifti_path)

# Try DICOM if NIfTI not found
if not volume_node:
    dicom_dir = os.path.join(patient_dir, "PATIENT_DICOM")
    if os.path.isdir(dicom_dir):
        print(f"Loading DICOM from: {dicom_dir}")
        # Find DICOM files
        dicom_files = []
        for root, dirs, files in os.walk(dicom_dir):
            for f in files:
                fpath = os.path.join(root, f)
                dicom_files.append(fpath)
        
        if dicom_files:
            # Use DICOM module to load
            from DICOMLib import DICOMUtils
            with DICOMUtils.TemporaryDICOMDatabase() as db:
                DICOMUtils.importDicom(dicom_dir, db)
                patientUIDs = db.patients()
                if patientUIDs:
                    DICOMUtils.loadPatientByUID(patientUIDs[0])
            
            # Get the loaded volume
            volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
            if volume_nodes:
                volume_node = volume_nodes[-1]

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set abdominal soft tissue window/level for liver visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Liver window: W=150, L=60 (good for liver parenchyma)
        displayNode.SetWindow(150)
        displayNode.SetLevel(60)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background volume in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Center on the liver region (typically in the upper abdomen)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        # Adjust to liver region (slightly to the right and superior)
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2] + 20)  # Move slightly superior
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(center[0] - 30)  # Move to right side where liver is
    
    print(f"CT loaded with liver window (W=150, L=60)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Volume spacing: {volume_node.GetSpacing()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for liver 3D model export task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
export PATIENT_NUM IRCADB_DIR
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_ircadb_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

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
take_screenshot /tmp/liver_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Liver 3D Model Export for Surgical Planning"
echo "=================================================="
echo ""
echo "A surgeon needs 3D-printable models of the patient's liver and tumors."
echo ""
echo "Your goal:"
echo "  1. Open Segment Editor module"
echo "  2. Create segmentation with segments: 'Liver' and 'Tumor'"
echo "  3. Segment the liver parenchyma (excluding tumors)"
echo "  4. Segment any tumor tissue"
echo "  5. Apply smoothing to segments"
echo "  6. Export liver as STL: ~/Documents/SlicerData/IRCADb/liver_model.stl"
echo "  7. Export tumor as STL: ~/Documents/SlicerData/IRCADb/tumor_model.stl"
echo "  8. Create report: ~/Documents/SlicerData/IRCADb/model_report.json"
echo ""
echo "Report format:"
echo "  {\"liver_volume_ml\": X, \"tumor_volume_ml\": Y, \"tumor_count\": N,"
echo "   \"smoothing_applied\": true, \"models_exported\": [...]}"
echo ""