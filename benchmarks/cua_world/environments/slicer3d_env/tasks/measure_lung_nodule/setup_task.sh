#!/bin/bash
echo "=== Setting up Lung Nodule Measurement Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$EXPORT_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Clear previous task state
rm -f /tmp/lung_nodule_result.json 2>/dev/null || true
rm -f "$EXPORT_DIR/nodule_measurement.json" 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial state of output file (for anti-gaming)
echo "0" > /tmp/initial_measurement_exists.txt

# ============================================================
# Prepare LIDC-IDRI data
# ============================================================
echo "Preparing LIDC-IDRI chest CT data..."

export PATIENT_ID GROUND_TRUTH_DIR LIDC_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || {
    echo "WARNING: LIDC data preparation had issues, continuing..."
}

# Check if patient ID was updated
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi
echo "$PATIENT_ID" > /tmp/lung_nodule_patient_id.txt

# Verify DICOM directory
DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
if [ ! -d "$DICOM_DIR" ]; then
    # Try alternative locations
    DICOM_DIR=$(find "$LIDC_DIR" -type d -name "DICOM" 2>/dev/null | head -1)
    if [ -z "$DICOM_DIR" ]; then
        echo "ERROR: DICOM directory not found"
        exit 1
    fi
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "Found $DICOM_COUNT files in DICOM directory: $DICOM_DIR"

if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Insufficient DICOM files"
    exit 1
fi

# ============================================================
# Get nodule location from ground truth
# ============================================================
GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_nodules.json"

NODULE_X="0"
NODULE_Y="0"
NODULE_Z="0"
GT_DIAMETER="0"

if [ -f "$GT_FILE" ]; then
    echo "Reading ground truth nodule data..."
    NODULE_INFO=$(python3 << PYEOF
import json
import sys

try:
    with open("$GT_FILE", "r") as f:
        data = json.load(f)
    
    nodules = data.get("nodules", [])
    if nodules:
        # Use the first nodule (or the largest one)
        nodule = nodules[0]
        centroid = nodule.get("centroid_xyz", [0, 0, 0])
        diameter = nodule.get("diameter_mm", 0)
        
        # Also check for diameter in pixels and convert
        if diameter == 0:
            diameter_px = nodule.get("diameter_pixels", 10)
            # Estimate mm assuming ~0.7mm pixel spacing
            diameter = diameter_px * 0.7
        
        print(f"{centroid[0]},{centroid[1]},{centroid[2]},{diameter}")
    else:
        # Default location if no nodules found
        print("0,0,0,10")
except Exception as e:
    print(f"0,0,0,10", file=sys.stderr)
    print("0,0,0,10")
PYEOF
)
    
    NODULE_X=$(echo "$NODULE_INFO" | cut -d',' -f1)
    NODULE_Y=$(echo "$NODULE_INFO" | cut -d',' -f2)
    NODULE_Z=$(echo "$NODULE_INFO" | cut -d',' -f3)
    GT_DIAMETER=$(echo "$NODULE_INFO" | cut -d',' -f4)
    
    echo "Nodule location: ($NODULE_X, $NODULE_Y, $NODULE_Z)"
    echo "Ground truth diameter: $GT_DIAMETER mm"
else
    echo "WARNING: Ground truth file not found at $GT_FILE"
    echo "Using default estimated nodule location"
    # Estimate typical lung nodule location for LIDC data
    NODULE_X="-30"
    NODULE_Y="-150"
    NODULE_Z="-100"
    GT_DIAMETER="10"
fi

# Save ground truth for verification
cat > /tmp/nodule_ground_truth.json << GTEOF
{
    "patient_id": "$PATIENT_ID",
    "nodule_centroid_ras": [$NODULE_X, $NODULE_Y, $NODULE_Z],
    "ground_truth_diameter_mm": $GT_DIAMETER,
    "dicom_dir": "$DICOM_DIR"
}
GTEOF
chmod 644 /tmp/nodule_ground_truth.json

# ============================================================
# Kill any existing Slicer and launch fresh
# ============================================================
echo "Launching 3D Slicer..."
pkill -f "Slicer" 2>/dev/null || true
sleep 3

# Create startup Python script
cat > /tmp/load_lung_ct.py << PYEOF
import slicer
import os
import json

print("Loading LIDC lung CT data...")

dicom_dir = "$DICOM_DIR"
nodule_x = float($NODULE_X)
nodule_y = float($NODULE_Y)
nodule_z = float($NODULE_Z)

# Import DICOM data
try:
    from DICOMLib import DICOMUtils
    
    # Create temporary DICOM database
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicom_dir, db)
        patientUIDs = db.patients()
        if patientUIDs:
            DICOMUtils.loadPatientByUID(patientUIDs[0])
            print(f"Loaded patient: {patientUIDs[0]}")
        else:
            print("No patients found in DICOM database")
except Exception as e:
    print(f"DICOM import error: {e}")
    # Try alternative loading method
    try:
        slicer.util.loadVolume(dicom_dir)
    except:
        pass

# Wait for loading
slicer.app.processEvents()

# Create fiducial at nodule location
print(f"Creating fiducial at nodule location: ({nodule_x}, {nodule_y}, {nodule_z})")
markupsNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLMarkupsFiducialNode", "CAD_Nodule_Location")
markupsNode.AddControlPoint(nodule_x, nodule_y, nodule_z, "CAD_Nodule_Location")

# Configure fiducial display - make it prominent
displayNode = markupsNode.GetDisplayNode()
if displayNode:
    displayNode.SetSelectedColor(1.0, 1.0, 0.0)  # Yellow
    displayNode.SetColor(1.0, 1.0, 0.0)  # Yellow
    displayNode.SetPointLabelsVisibility(True)
    displayNode.SetTextScale(4.0)
    displayNode.SetGlyphScale(5.0)
    displayNode.SetGlyphType(slicer.vtkMRMLMarkupsDisplayNode.Sphere3D)

# Set lung window/level on volume
volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volumeNodes:
    volumeNode = volumeNodes[0]
    displayNode = volumeNode.GetDisplayNode()
    if displayNode:
        displayNode.SetAutoWindowLevel(False)
        displayNode.SetWindow(1500)  # Lung window
        displayNode.SetLevel(-600)   # Lung level
        print("Set lung window/level (W:1500, L:-600)")

# Navigate slice views to nodule location
layoutManager = slicer.app.layoutManager()
for sliceViewName in ['Red', 'Yellow', 'Green']:
    sliceWidget = layoutManager.sliceWidget(sliceViewName)
    if sliceWidget:
        sliceNode = sliceWidget.mrmlSliceNode()
        sliceNode.JumpSlice(nodule_x, nodule_y, nodule_z)

# Also center 3D view
threeDWidget = layoutManager.threeDWidget(0)
if threeDWidget:
    threeDView = threeDWidget.threeDView()
    threeDView.resetFocalPoint()

print("Lung CT loaded with fiducial at nodule location")
print("Task: Navigate to the fiducial and measure the nodule diameter using Line markup tool")
PYEOF

chmod 644 /tmp/load_lung_ct.py
chown ga:ga /tmp/load_lung_ct.py

# Launch Slicer with the startup script
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_lung_ct.py > /tmp/slicer_lung_startup.log 2>&1" &
SLICER_PID=$!

echo "Waiting for Slicer to start and load data..."
sleep 15

# Wait for Slicer window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "Slicer window detected"
        break
    fi
    sleep 2
done

# Give extra time for DICOM import
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Lung Nodule Measurement Task Setup Complete ==="
echo ""
echo "Patient ID: $PATIENT_ID"
echo "Nodule location (RAS): ($NODULE_X, $NODULE_Y, $NODULE_Z)"
echo "Expected diameter: ~${GT_DIAMETER}mm"
echo ""
echo "INSTRUCTIONS:"
echo "1. Find the yellow 'CAD_Nodule_Location' fiducial marker"
echo "2. Navigate to that location using the slice views"
echo "3. Find the slice where the nodule appears largest"
echo "4. Use the Line markup tool to measure the nodule diameter"
echo "5. Export measurement to: $EXPORT_DIR/nodule_measurement.json"
echo ""