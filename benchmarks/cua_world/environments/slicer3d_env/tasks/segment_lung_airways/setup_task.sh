#!/bin/bash
echo "=== Setting up Segment Lung Airways Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Prepare LIDC data
# ============================================================
LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
PATIENT_ID="LIDC-IDRI-0001"

mkdir -p "$LIDC_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

echo "Preparing LIDC chest CT data..."
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" 2>&1 || {
    echo "WARNING: LIDC data preparation had issues, continuing..."
}

# Get the patient ID that was actually used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
echo "Patient ID: $PATIENT_ID"
echo "DICOM directory: $DICOM_DIR"

# Verify DICOM data exists
DICOM_COUNT=0
if [ -d "$DICOM_DIR" ]; then
    DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
fi
echo "Found $DICOM_COUNT DICOM files"

if [ "$DICOM_COUNT" -lt 50 ]; then
    echo "WARNING: Expected more DICOM files, data may be incomplete"
fi

# ============================================================
# Record initial state for verification
# ============================================================
echo "Recording initial state..."

# Count existing segmentation files
INITIAL_SEG_COUNT=$(ls -1 "$EXPORT_DIR"/*.seg.nrrd "$EXPORT_DIR"/*.nrrd 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SEG_COUNT" > /tmp/initial_segmentation_count.txt

# Remove any previous airways segmentation (clean slate)
rm -f "$EXPORT_DIR/airways_segmentation.seg.nrrd" 2>/dev/null || true
rm -f "$EXPORT_DIR/airways*.nrrd" 2>/dev/null || true

# Save setup info
cat > /tmp/task_setup_info.json << EOF
{
    "patient_id": "$PATIENT_ID",
    "dicom_dir": "$DICOM_DIR",
    "dicom_file_count": $DICOM_COUNT,
    "export_dir": "$EXPORT_DIR",
    "expected_output": "$EXPORT_DIR/airways_segmentation.seg.nrrd",
    "setup_timestamp": $(date +%s)
}
EOF

# ============================================================
# Kill any existing Slicer and launch fresh
# ============================================================
echo "Preparing 3D Slicer..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Ensure X display is available
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Slicer
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!

# Wait for Slicer window to appear
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected after ${i}s"
        break
    fi
    sleep 2
done

# Additional wait for Slicer to fully initialize
sleep 5

# Maximize Slicer window
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    echo "Slicer window maximized"
fi

# ============================================================
# Load DICOM data into Slicer
# ============================================================
echo "Loading DICOM data into Slicer..."

# Create Python script to load DICOM
cat > /tmp/load_lidc_dicom.py << 'PYEOF'
import slicer
import os
import sys

dicom_dir = os.environ.get("DICOM_DIR", "/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0001/DICOM")
print(f"Loading DICOM from: {dicom_dir}")

try:
    from DICOMLib import DICOMUtils
    
    # Import DICOM files to database
    DICOMUtils.importDicom(dicom_dir)
    print("DICOM import complete")
    
    # Load the series
    patientUIDs = slicer.dicomDatabase.patients()
    loaded = False
    
    for patientUID in patientUIDs:
        studies = slicer.dicomDatabase.studiesForPatient(patientUID)
        for study in studies:
            series_list = slicer.dicomDatabase.seriesForStudy(study)
            for series in series_list:
                files = slicer.dicomDatabase.filesForSeries(series)
                if len(files) > 50:  # Main CT series
                    print(f"Loading series with {len(files)} files...")
                    loadedNodes = DICOMUtils.loadSeriesByUID([series])
                    if loadedNodes:
                        for node in loadedNodes:
                            if node.IsA("vtkMRMLScalarVolumeNode"):
                                # Set lung window/level
                                displayNode = node.GetDisplayNode()
                                if displayNode:
                                    displayNode.SetAutoWindowLevel(False)
                                    displayNode.SetWindow(1500)
                                    displayNode.SetLevel(-500)
                                print(f"Loaded volume: {node.GetName()}")
                                loaded = True
                        break
            if loaded:
                break
        if loaded:
            break
    
    if loaded:
        print("SUCCESS: CT volume loaded")
    else:
        print("WARNING: No volume loaded")

except Exception as e:
    print(f"ERROR loading DICOM: {e}")
    import traceback
    traceback.print_exc()

print("Load script complete")
PYEOF

# Set environment and run script
export DICOM_DIR="$DICOM_DIR"

# Use xdotool to open Python console and run the script
sleep 2
DISPLAY=:1 xdotool key ctrl+3  # Toggle Python interactor
sleep 2
DISPLAY=:1 xdotool type "exec(open('/tmp/load_lidc_dicom.py').read())"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 15  # Wait for DICOM import and loading

# Close Python console
DISPLAY=:1 xdotool key ctrl+3
sleep 1

# ============================================================
# Take initial screenshot
# ============================================================
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Segment the lung airways from the chest CT"
echo ""
echo "Instructions:"
echo "1. Open Segment Editor module"
echo "2. Create a segment named 'Airways'"
echo "3. Use Threshold effect (-1024 to -900 HU for air)"
echo "4. Use Islands effect to keep only the airway tree"
echo "5. Click 'Show 3D' to visualize"
echo "6. Save to: ~/Documents/SlicerData/Exports/airways_segmentation.seg.nrrd"
echo ""
echo "Expected output: Trachea and bronchi as a single connected structure"
echo "                 (NOT including external air around patient)"