#!/bin/bash
echo "=== Setting up Pulmonary Artery Measurement Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create necessary directories
LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$LIDC_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Remove any previous measurement file (clean slate)
rm -f "$EXPORTS_DIR/pa_measurement.json" 2>/dev/null || true
rm -f /tmp/pa_measurement_result.json 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_measurement_exists.txt
ls -la "$EXPORTS_DIR"/*.json 2>/dev/null > /tmp/initial_exports_list.txt || echo "none" > /tmp/initial_exports_list.txt

# ============================================================
# Prepare LIDC chest CT data
# ============================================================
echo "Preparing chest CT data from LIDC-IDRI..."

PATIENT_ID="LIDC-IDRI-0001"

# Check if data preparation script exists
if [ -f /workspace/scripts/prepare_lidc_data.sh ]; then
    /workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"
else
    echo "Data preparation script not found, attempting direct setup..."
fi

# Get the patient ID that was prepared
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

# Verify data exists
if [ -d "$DICOM_DIR" ]; then
    DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
    echo "Found $DICOM_COUNT DICOM files in $DICOM_DIR"
else
    echo "WARNING: DICOM directory not found at $DICOM_DIR"
    # Try alternative locations
    for alt_dir in "$LIDC_DIR"/*/DICOM "$LIDC_DIR/DICOM" /home/ga/Documents/SlicerData/SampleData; do
        if [ -d "$alt_dir" ] && [ "$(ls -A "$alt_dir" 2>/dev/null)" ]; then
            DICOM_DIR="$alt_dir"
            echo "Using alternative data directory: $DICOM_DIR"
            break
        fi
    done
fi

# Save metadata for verification
cat > /tmp/task_metadata.json << EOF
{
    "patient_id": "$PATIENT_ID",
    "dicom_dir": "$DICOM_DIR",
    "output_file": "$EXPORTS_DIR/pa_measurement.json",
    "expected_range_mm": {"min": 15, "max": 45},
    "normal_range_mm": {"min": 20, "max": 29},
    "start_time": $(cat /tmp/task_start_time.txt)
}
EOF

# ============================================================
# Launch 3D Slicer
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
export DISPLAY=:1
xhost +local: 2>/dev/null || true

sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!
echo "Slicer launched with PID: $SLICER_PID"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 8

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# ============================================================
# Load chest CT data into Slicer
# ============================================================
echo "Loading chest CT data into Slicer..."

LOAD_SCRIPT=$(mktemp /tmp/load_ct.XXXXXX.py)
cat > "$LOAD_SCRIPT" << PYEOF
import slicer
import os
import glob

dicom_dir = "$DICOM_DIR"
print(f"Loading DICOM from: {dicom_dir}")

try:
    from DICOMLib import DICOMUtils
    
    # Open temporary DICOM database
    DICOMUtils.openTemporaryDatabase()
    
    # Import DICOM files
    if os.path.isdir(dicom_dir):
        DICOMUtils.importDicom(dicom_dir)
        
        # Load all patients
        patientUIDs = slicer.dicomDatabase.patients()
        print(f"Found {len(patientUIDs)} patient(s)")
        
        if patientUIDs:
            DICOMUtils.loadPatientByUID(patientUIDs[0])
            print("DICOM loaded successfully")
        else:
            print("No patients found in DICOM database")
    else:
        print(f"DICOM directory not found: {dicom_dir}")
        
        # Try loading NRRD files as fallback
        sample_dir = "/home/ga/Documents/SlicerData/SampleData"
        nrrd_files = glob.glob(os.path.join(sample_dir, "*.nrrd"))
        if nrrd_files:
            slicer.util.loadVolume(nrrd_files[0])
            print(f"Loaded fallback volume: {nrrd_files[0]}")
            
except Exception as e:
    print(f"Error loading DICOM: {e}")
    
    # Fallback: try loading any available volume
    try:
        sample_file = "/home/ga/Documents/SlicerData/SampleData/CTChest.nrrd"
        if os.path.exists(sample_file):
            slicer.util.loadVolume(sample_file)
            print(f"Loaded fallback: {sample_file}")
    except Exception as e2:
        print(f"Fallback also failed: {e2}")

# Apply mediastinal window (W=400, L=40) for viewing PA
try:
    volumeNodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    if volumeNodes:
        volumeNode = volumeNodes[0]
        displayNode = volumeNode.GetDisplayNode()
        if displayNode:
            # Mediastinal window settings
            displayNode.SetWindow(400)
            displayNode.SetLevel(40)
            displayNode.SetAutoWindowLevel(False)
            print("Applied mediastinal window settings (W=400, L=40)")
except Exception as e:
    print(f"Could not apply window settings: {e}")

# Reset views
slicer.util.resetSliceViews()
print("Setup complete")
PYEOF

# Execute the load script
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$LOAD_SCRIPT" > /tmp/slicer_load.log 2>&1 &
sleep 15

# Clean up
rm -f "$LOAD_SCRIPT"

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo "Patient ID: $PATIENT_ID"
echo "Data directory: $DICOM_DIR"
echo "Output file: $EXPORTS_DIR/pa_measurement.json"
echo ""
echo "TASK: Navigate to the pulmonary artery bifurcation level in the axial view,"
echo "      measure the main PA diameter using the ruler/line markup tool,"
echo "      and save your measurement to the output JSON file."
echo ""
echo "Clinical Reference:"
echo "  - Normal PA diameter: <= 25mm"
echo "  - Borderline: 25-29mm"
echo "  - Enlarged (pulmonary HTN): > 29mm"