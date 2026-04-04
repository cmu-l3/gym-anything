#!/bin/bash
echo "=== Setting up Bronchial Wall Thickness Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
PATIENT_ID="LIDC-IDRI-0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Prepare LIDC data (downloads real data if not exists)
echo "Preparing LIDC-IDRI chest CT data..."
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

echo "Using patient: $PATIENT_ID"

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

# Verify DICOM data exists
if [ ! -d "$DICOM_DIR" ]; then
    # Try to find DICOM directory
    DICOM_DIR=$(find "$LIDC_DIR" -type d -name "DICOM" 2>/dev/null | head -1)
    if [ -z "$DICOM_DIR" ]; then
        echo "ERROR: DICOM directory not found"
        exit 1
    fi
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "Found $DICOM_COUNT DICOM files in: $DICOM_DIR"

if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files ($DICOM_COUNT)"
    exit 1
fi

# Clean up any previous task outputs
rm -f /tmp/bronchial_task_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/bronchial_measurements.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/bronchial_report.json" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "patient_id": "$PATIENT_ID",
    "dicom_dir": "$DICOM_DIR",
    "dicom_count": $DICOM_COUNT,
    "measurement_exists": false,
    "report_exists": false
}
EOF

# Create Slicer Python script to load DICOM and set lung window
cat > /tmp/load_chest_ct.py << 'PYEOF'
import slicer
import os
from DICOMLib import DICOMUtils

dicom_dir = os.environ.get("DICOM_DIR", "/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0001/DICOM")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

print(f"Loading chest CT for patient: {patient_id}")
print(f"DICOM directory: {dicom_dir}")

# Import DICOM
try:
    # Use DICOMUtils for importing
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicom_dir, db)
        patientUIDs = db.patients()
        if patientUIDs:
            loadedNodeIDs = DICOMUtils.loadPatientByUID(patientUIDs[0])
            print(f"Loaded {len(loadedNodeIDs)} volume(s)")
except Exception as e:
    print(f"DICOMUtils method failed: {e}")
    print("Trying direct volume load...")
    # Fallback: try loading as volume directly
    import glob
    dcm_files = glob.glob(os.path.join(dicom_dir, "**", "*"), recursive=True)
    dcm_files = [f for f in dcm_files if os.path.isfile(f)]
    if dcm_files:
        try:
            volume = slicer.util.loadVolume(dcm_files[0])
            if volume:
                print(f"Loaded volume: {volume.GetName()}")
        except Exception as e2:
            print(f"Direct load also failed: {e2}")

# Get the loaded volume and configure display
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volume_nodes:
    volume_node = volume_nodes[0]
    volume_node.SetName("ChestCT")
    
    # Set lung window for airway visualization
    display_node = volume_node.GetDisplayNode()
    if display_node:
        display_node.SetAutoWindowLevel(False)
        display_node.SetWindow(1500)  # Lung window width
        display_node.SetLevel(-600)   # Lung window level
        print("Set lung window (W:1500, L:-600) for airway visualization")
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        slice_logic = slicer.app.layoutManager().sliceWidget(color).sliceLogic()
        slice_composite = slice_logic.GetSliceCompositeNode()
        slice_composite.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to upper chest area (where bronchi are visible)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # For axial view (Red), go to upper third of volume (where upper lobe bronchi are)
    z_range = bounds[5] - bounds[4]
    upper_third_z = bounds[4] + (z_range * 0.65)  # Upper portion of chest
    
    red_logic = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
    red_logic.GetSliceNode().SetSliceOffset(upper_third_z)
    
    # Center the other views
    center_y = (bounds[2] + bounds[3]) / 2
    center_x = (bounds[0] + bounds[1]) / 2
    
    green_logic = slicer.app.layoutManager().sliceWidget("Green").sliceLogic()
    green_logic.GetSliceNode().SetSliceOffset(center_y)
    
    yellow_logic = slicer.app.layoutManager().sliceWidget("Yellow").sliceLogic()
    yellow_logic.GetSliceNode().SetSliceOffset(center_x)
    
    print(f"Volume loaded: {volume_node.GetName()}")
    print(f"Dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Positioned at upper chest for bronchus visualization")
else:
    print("WARNING: No volume loaded")

print("Setup complete - ready for bronchial wall measurement task")
PYEOF

# Set environment variables for the Python script
export DICOM_DIR="$DICOM_DIR"
export PATIENT_ID="$PATIENT_ID"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the setup script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 DICOM_DIR="$DICOM_DIR" PATIENT_ID="$PATIENT_ID" \
    /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 15

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/bronchial_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Bronchial Wall Thickness Assessment"
echo "=========================================="
echo ""
echo "You are given a chest CT scan. Measure bronchial wall thickness"
echo "to assess airway remodeling (a key COPD biomarker)."
echo ""
echo "Your task:"
echo "  1. Navigate to the right upper lobe bronchus area"
echo "  2. Find the RB1 segmental bronchus (appears circular)"
echo "  3. Measure with Markups ruler tool:"
echo "     - Outer diameter (Do): wall to wall"
echo "     - Inner diameter (Di): lumen to lumen"
echo "  4. Calculate: WA% = [(Do² - Di²) / Do²] × 100"
echo "  5. Classify:"
echo "     - Normal: WA% < 60%"
echo "     - Mildly Thickened: 60-70%"
echo "     - Moderately Thickened: 70-80%"
echo "     - Severely Thickened: > 80%"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/LIDC/bronchial_measurements.mrk.json"
echo "  - ~/Documents/SlicerData/LIDC/bronchial_report.json"
echo ""
echo "Tip: Segmental bronchi are typically 5-8mm outer diameter."
echo ""