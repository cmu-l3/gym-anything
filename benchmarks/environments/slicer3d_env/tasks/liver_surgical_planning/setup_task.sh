#!/bin/bash
echo "=== Setting up Liver Surgical Planning Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="5"

# Prepare IRCADb data (downloads real data if not exists)
echo "Preparing 3D-IRCADb data..."
export PATIENT_NUM GROUND_TRUTH_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get the patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
DICOM_DIR="$PATIENT_DIR/PATIENT_DICOM"
NIFTI_CT="$PATIENT_DIR/patient_${PATIENT_NUM}_ct.nii.gz"

echo "Using patient: $PATIENT_NUM"

# Verify data exists
if [ -f "$NIFTI_CT" ]; then
    echo "Using NIfTI CT: $NIFTI_CT"
elif [ -d "$DICOM_DIR" ] && [ "$(find "$DICOM_DIR" -type f | wc -l)" -gt 10 ]; then
    echo "Using DICOM directory: $DICOM_DIR"
else
    echo "ERROR: No CT data found for patient $PATIENT_NUM"
    exit 1
fi

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state
rm -f /tmp/liver_task_result.json 2>/dev/null || true
rm -f "$IRCADB_DIR/agent_segmentation.nii.gz" 2>/dev/null || true
rm -f "$IRCADB_DIR/surgical_report.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create a Slicer Python script to load the CT volume
cat > /tmp/load_ircadb_ct.py << PYEOF
import slicer
import os

patient_dir = "$PATIENT_DIR"
patient_num = "$PATIENT_NUM"
nifti_ct = "$NIFTI_CT"
dicom_dir = "$DICOM_DIR"

print(f"Loading IRCADb patient {patient_num} CT scan...")

volume_node = None

# Prefer NIfTI if available
if os.path.exists(nifti_ct):
    print(f"Loading NIfTI CT: {nifti_ct}")
    volume_node = slicer.util.loadVolume(nifti_ct)
    if volume_node:
        volume_node.SetName("AbdominalCT")
        print(f"  Loaded: {volume_node.GetName()}")

# Fall back to DICOM import
if volume_node is None and os.path.isdir(dicom_dir):
    print(f"Loading from DICOM: {dicom_dir}")
    from DICOMLib import DICOMUtils

    if not slicer.dicomDatabase or not slicer.dicomDatabase.isOpen:
        db_dir = os.path.join(slicer.app.temporaryPath, "DICOM")
        os.makedirs(db_dir, exist_ok=True)
        slicer.dicomDatabase.openDatabase(os.path.join(db_dir, "ctkDICOM.sql"))

    DICOMUtils.importDicom(dicom_dir)
    patientUIDs = slicer.dicomDatabase.patients()

    for patient in patientUIDs:
        studies = slicer.dicomDatabase.studiesForPatient(patient)
        for study in studies:
            series = slicer.dicomDatabase.seriesForStudy(study)
            for s in series:
                files = slicer.dicomDatabase.filesForSeries(s)
                if len(files) > 50:
                    loadedNodes = DICOMUtils.loadSeriesByUID([s])
                    if loadedNodes:
                        volume_node = loadedNodes[0]
                        volume_node.SetName("AbdominalCT")
                        break
            if volume_node:
                break
        if volume_node:
            break

if volume_node:
    # Set abdominal CT window/level (portal venous phase)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    slicer.util.resetSliceViews()

    # Center on data
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

    print(f"CT loaded with abdominal window (W=400, L=40)")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for liver surgical planning task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
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

# Wait for CT to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/liver_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Liver Surgical Planning"
echo "=============================="
echo ""
echo "You are given an abdominal CT scan of a patient with liver tumors"
echo "being evaluated for surgical resection."
echo ""
echo "Your goal:"
echo "  1. Segment the liver parenchyma"
echo "  2. Segment all visible liver tumors"
echo "  3. Segment the portal vein (large vessel entering the liver)"
echo "  4. Determine minimum tumor-to-portal-vein distance"
echo "  5. Report tumor volume, tumor count, min distance, and vascular invasion"
echo ""
echo "Save your outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/IRCADb/agent_segmentation.nii.gz"
echo "    (Label 1=liver, Label 2=tumor, Label 3=portal vein)"
echo "  - Report: ~/Documents/SlicerData/IRCADb/surgical_report.json"
echo ""
