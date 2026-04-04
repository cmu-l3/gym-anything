#!/bin/bash
echo "=== Setting up Azygos Vein Diameter Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare LIDC data (downloads real data if not exists)
echo "Preparing LIDC-IDRI chest CT data..."
export PATIENT_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"

# Verify DICOM directory exists
if [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found at $DICOM_DIR"
    # Try to find any DICOM files
    DICOM_DIR=$(find "$LIDC_DIR" -type d -name "DICOM" 2>/dev/null | head -1)
    if [ -z "$DICOM_DIR" ] || [ ! -d "$DICOM_DIR" ]; then
        echo "ERROR: No DICOM directory found in $LIDC_DIR"
        ls -la "$LIDC_DIR" 2>/dev/null || true
        exit 1
    fi
    echo "Found alternative DICOM directory: $DICOM_DIR"
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "Found $DICOM_COUNT DICOM files"

if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files ($DICOM_COUNT)"
    exit 1
fi

# Record initial state
rm -f /tmp/azygos_task_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/azygos_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/azygos_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time
echo "$(date -Iseconds)" > /tmp/task_start_timestamp

# Generate ground truth for azygos measurement (approximate reference)
# This creates a reference measurement based on anatomical expectations
echo "Generating reference measurements..."
python3 << 'PYEOF'
import os
import json

gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

# For LIDC lung cancer screening CTs, azygos vein is typically visible
# Normal range: 7-10mm in supine position
# Reference anatomical location: right paratracheal, at level of azygos arch
# Approximate z-coordinate: 20-40mm above carina level

gt_data = {
    "patient_id": patient_id,
    "structure": "azygos_vein",
    "measurement_location": "azygos_arch",
    "expected_diameter_range_mm": [5, 15],
    "normal_diameter_max_mm": 10,
    "anatomical_region": {
        "description": "Right paratracheal region, at azygos arch level",
        "relative_to_carina": "at_or_above",
        "lateral_position": "right_of_trachea",
        "anterior_posterior": "posterior_to_SVC"
    },
    "classification_thresholds": {
        "normal": {"max": 10},
        "mildly_dilated": {"min": 10, "max": 15},
        "dilated": {"min": 15}
    },
    "notes": "Reference values for typical adult chest CT. Azygos diameter can vary with patient positioning and volume status."
}

os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{patient_id}_azygos_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth reference saved to {gt_path}")
PYEOF

# Create a Slicer Python script to load the DICOM and set mediastinal window
cat > /tmp/load_lidc_ct.py << PYEOF
import slicer
import os
from DICOMLib import DICOMUtils

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading LIDC chest CT for patient: {patient_id}")
print(f"DICOM directory: {dicom_dir}")

# Import DICOM data
try:
    # Get the DICOM database
    dicomBrowser = slicer.modules.dicom.widgetRepresentation().self()
    
    # Import the DICOM folder
    print("Importing DICOM files...")
    DICOMUtils.importDicom(dicom_dir)
    
    # Load the patient series
    print("Loading patient data...")
    patientUIDs = slicer.dicomDatabase.patients()
    
    loadedNodeIDs = []
    if patientUIDs:
        # Get studies for first patient
        for patientUID in patientUIDs[:1]:
            studies = slicer.dicomDatabase.studiesForPatient(patientUID)
            for study in studies[:1]:
                series = slicer.dicomDatabase.seriesForStudy(study)
                for serie in series[:1]:
                    # Load this series
                    loadedNodeIDs.extend(DICOMUtils.loadSeriesByUID([serie]))
    
    if loadedNodeIDs:
        print(f"Loaded {len(loadedNodeIDs)} volume(s)")
        
        # Get the loaded volume node
        volumeNode = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])
        if volumeNode:
            volumeNode.SetName("ChestCT")
            
            # Set mediastinal window/level for vessel visualization
            displayNode = volumeNode.GetDisplayNode()
            if displayNode:
                # Mediastinal window: W=400, L=40
                displayNode.SetWindow(400)
                displayNode.SetLevel(40)
                displayNode.SetAutoWindowLevel(False)
                print("Set mediastinal window (W=400, L=40) for vessel visualization")
            
            # Set as background in all views
            for color in ["Red", "Green", "Yellow"]:
                sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
                sliceCompositeNode.SetBackgroundVolumeID(volumeNode.GetID())
            
            # Reset views
            slicer.util.resetSliceViews()
            
            # Navigate to approximate level of azygos arch (upper thorax)
            # The azygos arch is typically at or just above the carina
            bounds = [0]*6
            volumeNode.GetBounds(bounds)
            z_center = (bounds[4] + bounds[5]) / 2
            z_upper = bounds[5] - (bounds[5] - bounds[4]) * 0.35  # Upper third
            
            # Set axial view to upper thorax level
            redSliceNode = slicer.app.layoutManager().sliceWidget("Red").sliceLogic().GetSliceNode()
            redSliceNode.SetSliceOffset(z_upper)
            
            print(f"Navigated to upper thorax level (z={z_upper:.1f}mm)")
            print(f"Volume bounds: z={bounds[4]:.1f} to {bounds[5]:.1f}mm")
    else:
        print("WARNING: No volumes loaded from DICOM")
        
except Exception as e:
    print(f"Error loading DICOM: {e}")
    # Try alternative loading method
    try:
        import glob
        dcm_files = glob.glob(os.path.join(dicom_dir, "**/*"), recursive=True)
        dcm_files = [f for f in dcm_files if os.path.isfile(f)]
        if dcm_files:
            print(f"Trying to load first DICOM file directly...")
            volumeNode = slicer.util.loadVolume(dcm_files[0])
            if volumeNode:
                volumeNode.SetName("ChestCT")
                displayNode = volumeNode.GetDisplayNode()
                if displayNode:
                    displayNode.SetWindow(400)
                    displayNode.SetLevel(40)
                print("Loaded volume using direct file loading")
    except Exception as e2:
        print(f"Alternative loading also failed: {e2}")

print("Setup complete - ready for azygos vein measurement task")
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
sleep 15

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

# Wait for data to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/azygos_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Azygos Vein Diameter Assessment"
echo "======================================="
echo ""
echo "You are given a chest CT scan. The azygos vein diameter reflects"
echo "right-sided cardiac pressures and hepatic hemodynamics."
echo ""
echo "Your goal:"
echo "  1. Navigate to the level of the azygos arch (at/above carina level)"
echo "  2. Identify the azygos vein in the right paratracheal region"
echo "     (arches anteriorly over right mainstem bronchus to join SVC)"
echo "  3. Find the slice where the arch appears most rounded"
echo "  4. Measure the short-axis diameter using Markups ruler"
echo "  5. Classify: Normal (≤10mm), Mildly dilated (10-15mm), Dilated (>15mm)"
echo ""
echo "TIP: Use mediastinal window (W=400, L=40) for best vessel visualization"
echo ""
echo "Save your outputs:"
echo "  - Measurement: ~/Documents/SlicerData/LIDC/azygos_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/azygos_report.json"
echo "    (containing: diameter_mm, classification, slice_level, interpretation)"
echo ""