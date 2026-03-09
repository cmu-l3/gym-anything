#!/bin/bash
echo "=== Setting up Count Lung Nodules Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"

# Prepare LIDC data
echo "Preparing LIDC-IDRI data..."
/workspace/scripts/prepare_lidc_data.sh

if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
echo "Using patient: $PATIENT_ID"

# Verify DICOM exists
DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files: $DICOM_COUNT"
    exit 1
fi

# Record initial state
rm -f /tmp/count_nodules_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/nodule_markers.mrk.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create Python script to load CT with lung window and position to slice with nodules
cat > /tmp/setup_nodule_count.py << 'PYEOF'
import slicer
import os

dicom_dir = os.environ.get('DICOM_DIR', '/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0001/DICOM')
patient_id = os.environ.get('PATIENT_ID', 'LIDC-IDRI-0001')

print(f"Loading chest CT for {patient_id}...")

# Import DICOM
from DICOMLib import DICOMUtils

if not slicer.dicomDatabase or not slicer.dicomDatabase.isOpen:
    db_dir = os.path.join(slicer.app.temporaryPath, "DICOM")
    os.makedirs(db_dir, exist_ok=True)
    slicer.dicomDatabase.openDatabase(os.path.join(db_dir, "ctkDICOM.sql"))

print(f"Importing DICOM from {dicom_dir}...")
DICOMUtils.importDicom(dicom_dir)

# Load series
patientUIDs = slicer.dicomDatabase.patients()
loaded = False

for patient in patientUIDs:
    studies = slicer.dicomDatabase.studiesForPatient(patient)
    for study in studies:
        series = slicer.dicomDatabase.seriesForStudy(study)
        for s in series:
            files = slicer.dicomDatabase.filesForSeries(s)
            if len(files) > 50:
                loadedNodes = DICOMUtils.loadSeriesByUID([s])
                if loadedNodes:
                    loaded = True
                    break
    if loaded:
        break

if not loaded and patientUIDs:
    DICOMUtils.loadPatientByUID(patientUIDs[0])

# Configure with LUNG WINDOW (optimal for nodules)
volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volumeNodes:
    volumeNode = volumeNodes[0]
    volumeNode.SetName("ChestCT")

    displayNode = volumeNode.GetDisplayNode()
    if displayNode:
        # LUNG WINDOW: W=1500, L=-600 (nodules clearly visible)
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-600)
        displayNode.SetAutoWindowLevel(False)

    # Set as background
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volumeNode.GetID())

    # Position to a slice roughly in the middle of the lungs
    bounds = [0]*6
    volumeNode.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2  # Approximate center of thorax

    # Set axial slice to this position
    red_logic = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
    red_logic.SetSliceOffset(center_z)

    slicer.util.resetSliceViews()

    print(f"CT loaded with LUNG WINDOW (W=1500, L=-600)")
    print(f"Positioned to slice z={center_z:.1f}mm")

    # Save expected position for verification
    with open('/tmp/nodule_slice_position.txt', 'w') as f:
        f.write(f"{center_z:.2f}")

# Navigate to Markups
slicer.util.selectModule("Markups")

print("Setup complete - lung nodules should be visible as bright spots")
PYEOF

# Kill existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

export DICOM_DIR="$DICOM_DIR"
export PATIENT_ID="$PATIENT_ID"

# Launch Slicer
echo "Launching 3D Slicer with lung window..."
sudo -u ga DISPLAY=:1 DICOM_DIR="$DICOM_DIR" PATIENT_ID="$PATIENT_ID" /opt/Slicer/Slicer --python-script /tmp/setup_nodule_count.py > /tmp/slicer_launch.log 2>&1 &

wait_for_slicer 120
sleep 15  # Extra wait for DICOM import

# Configure window
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    focus_window "$WID"
fi

sleep 3
take_screenshot /tmp/nodule_initial.png ga

echo "=== Setup Complete ==="
