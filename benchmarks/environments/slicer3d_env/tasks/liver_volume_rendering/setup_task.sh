#!/bin/bash
echo "=== Setting up Liver Volume Rendering Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
PATIENT_NUM=5

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create directories
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Clean previous task outputs
rm -f "$EXPORTS_DIR/liver_volume_rendering.png" 2>/dev/null || true
rm -f /tmp/liver_vr_task_result.json 2>/dev/null || true

# Record initial state - check if expected output exists
EXPECTED_OUTPUT="$EXPORTS_DIR/liver_volume_rendering.png"
if [ -f "$EXPECTED_OUTPUT" ]; then
    INITIAL_OUTPUT_EXISTS="true"
    INITIAL_OUTPUT_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
else
    INITIAL_OUTPUT_EXISTS="false"
    INITIAL_OUTPUT_MTIME="0"
fi

cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_OUTPUT_EXISTS,
    "output_mtime": $INITIAL_OUTPUT_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Prepare IRCADb data
echo "Preparing IRCADb liver CT data..."
export PATIENT_NUM IRCADB_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get the patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

echo "Using IRCADb patient: $PATIENT_NUM"

# Find the CT data to load
CT_FILE=""
PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"

# Check for various data formats
if [ -d "$PATIENT_DIR/PATIENT_DICOM" ] && [ "$(ls -A $PATIENT_DIR/PATIENT_DICOM 2>/dev/null)" ]; then
    CT_FILE="$PATIENT_DIR/PATIENT_DICOM"
    echo "Found DICOM directory: $CT_FILE"
elif [ -f "$PATIENT_DIR/ct.nii.gz" ]; then
    CT_FILE="$PATIENT_DIR/ct.nii.gz"
    echo "Found NIfTI file: $CT_FILE"
elif [ -f "$IRCADB_DIR/amos_0001.nii.gz" ]; then
    CT_FILE="$IRCADB_DIR/amos_0001.nii.gz"
    echo "Found synthetic AMOS data: $CT_FILE"
fi

if [ -z "$CT_FILE" ]; then
    echo "ERROR: No CT data found!"
    ls -la "$IRCADB_DIR"
    ls -la "$PATIENT_DIR" 2>/dev/null || true
    exit 1
fi

# Save CT file path for export script
echo "$CT_FILE" > /tmp/ircadb_ct_file

# Kill any existing Slicer instances
echo "Cleaning up any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 3

# Launch 3D Slicer with the CT data
echo "Launching 3D Slicer with liver CT..."

if [ -d "$CT_FILE" ]; then
    # DICOM directory - use Slicer's DICOM import
    echo "Loading DICOM directory..."
    
    # Create a Python script to import DICOM
    cat > /tmp/load_dicom.py << 'PYEOF'
import slicer
import os

dicom_dir = os.environ.get('DICOM_DIR', '/home/ga/Documents/SlicerData/IRCADb/patient_5/PATIENT_DICOM')

try:
    from DICOMLib import DICOMUtils
    print(f"Importing DICOM from: {dicom_dir}")
    
    # Import DICOM
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicom_dir, db)
        patientUIDs = db.patients()
        if patientUIDs:
            DICOMUtils.loadPatientByUID(patientUIDs[0])
            print("DICOM loaded successfully")
        else:
            print("No patients found in DICOM database")
except Exception as e:
    print(f"DICOM import error: {e}")
    # Fallback: try loading as image sequence
    try:
        slicer.util.loadVolume(dicom_dir)
    except:
        pass

slicer.app.processEvents()
PYEOF

    export DICOM_DIR="$CT_FILE"
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_dicom.py > /tmp/slicer_launch.log 2>&1 &
else
    # NIfTI file - direct load
    echo "Loading NIfTI file: $CT_FILE"
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$CT_FILE" > /tmp/slicer_launch.log 2>&1 &
fi

SLICER_PID=$!
echo "Slicer PID: $SLICER_PID"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Additional wait for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
echo "Focusing Slicer window..."
for i in {1..10}; do
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Slicer window focused: $WID"
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 3
echo "Capturing initial screenshot..."
take_screenshot /tmp/liver_vr_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/liver_vr_initial.png ]; then
    SIZE=$(stat -c%s /tmp/liver_vr_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "CT data loaded in 3D Slicer."
echo "Data source: IRCADb patient $PATIENT_NUM (contrast-enhanced abdominal CT)"
echo ""
echo "TASK: Configure volume rendering to visualize the liver for surgical planning."
echo ""
echo "Steps:"
echo "  1. Go to Volume Rendering module"
echo "  2. Enable volume rendering (click eye icon)"
echo "  3. Configure transfer function for soft tissue"
echo "  4. Rotate 3D view to show liver clearly"
echo "  5. Save screenshot to: $EXPORTS_DIR/liver_volume_rendering.png"
echo ""