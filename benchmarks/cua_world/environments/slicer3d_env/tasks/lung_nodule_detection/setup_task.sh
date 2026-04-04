#!/bin/bash
echo "=== Setting up Lung Nodule Detection Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare LIDC data (downloads real data if not exists)
echo "Preparing LIDC-IDRI data..."
/workspace/scripts/prepare_lidc_data.sh

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"

# Verify DICOM files exist
DICOM_COUNT=$(find "$DICOM_DIR" -type f | wc -l)
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files found: $DICOM_COUNT"
    exit 1
fi
echo "Found $DICOM_COUNT DICOM files"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_nodules.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state
rm -f /tmp/lidc_task_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/agent_fiducials.fcsv" 2>/dev/null || true
rm -f "$LIDC_DIR/nodule_report.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create a Slicer Python script to load the CT and import DICOM
cat > /tmp/load_lidc_ct.py << PYEOF
import slicer
import os

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading LIDC-IDRI CT scan for {patient_id}...")

# Import DICOM data into Slicer's DICOM database
from DICOMLib import DICOMUtils

# Initialize DICOM database if needed
if not slicer.dicomDatabase or not slicer.dicomDatabase.isOpen:
    db_dir = os.path.join(slicer.app.temporaryPath, "DICOM")
    os.makedirs(db_dir, exist_ok=True)
    slicer.dicomDatabase.openDatabase(os.path.join(db_dir, "ctkDICOM.sql"))

# Import DICOM files
print(f"Importing DICOM files from {dicom_dir}...")
DICOMUtils.importDicom(dicom_dir)

# Load the imported series
print("Loading DICOM series into scene...")
patientUIDs = slicer.dicomDatabase.patients()
loaded = False

for patient in patientUIDs:
    studies = slicer.dicomDatabase.studiesForPatient(patient)
    for study in studies:
        series = slicer.dicomDatabase.seriesForStudy(study)
        for s in series:
            # Try to load each series
            files = slicer.dicomDatabase.filesForSeries(s)
            if len(files) > 50:  # Main CT series should have many slices
                print(f"  Loading series with {len(files)} files...")
                loadedNodes = DICOMUtils.loadSeriesByUID([s])
                if loadedNodes:
                    loaded = True
                    print(f"  Successfully loaded {len(loadedNodes)} node(s)")
                    break
    if loaded:
        break

if not loaded:
    # Fallback: try loading all series
    print("Attempting to load all available series...")
    DICOMUtils.loadPatientByUID(patientUIDs[0] if patientUIDs else "")

# Set up display - use MEDIASTINAL window (NOT lung window)
# Agent needs to realize they need to switch to lung window
volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volumeNodes:
    volumeNode = volumeNodes[0]
    volumeNode.SetName("ChestCT")

    # Set mediastinal window (default - NOT optimal for nodules)
    displayNode = volumeNode.GetDisplayNode()
    if displayNode:
        # Mediastinal window: W=400, L=40 (nodules are hard to see)
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volumeNode.GetID())

    # Reset views
    slicer.util.resetSliceViews()

    # Center on data
    bounds = [0]*6
    volumeNode.GetBounds(bounds)
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

    print(f"CT loaded with mediastinal window (W=400, L=40)")
    print(f"Volume dimensions: {volumeNode.GetImageData().GetDimensions()}")
else:
    print("WARNING: No volume nodes loaded")

print("Setup complete - ready for nodule detection task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_lidc_ct.py > /tmp/slicer_launch.log 2>&1 &

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

# Wait for DICOM import to complete
sleep 5

# Take initial screenshot
take_screenshot /tmp/lidc_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Lung Nodule Detection & Measurement"
echo "==========================================="
echo ""
echo "You are given a chest CT scan of a patient undergoing lung cancer screening."
echo ""
echo "Your goal:"
echo "  1. Find all lung nodules that are 3mm or larger in diameter"
echo "  2. Place a fiducial marker on each nodule (Markups module)"
echo "  3. Report each nodule's location (lobe) and diameter (mm)"
echo ""
echo "Note: You may need to adjust display settings to properly"
echo "visualize lung parenchyma (e.g., lung window: W=1500, L=-600)."
echo ""
echo "Save your outputs:"
echo "  - Fiducials: ~/Documents/SlicerData/LIDC/agent_fiducials.fcsv"
echo "  - Report: ~/Documents/SlicerData/LIDC/nodule_report.json"
echo ""
