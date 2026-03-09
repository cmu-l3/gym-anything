#!/bin/bash
echo "=== Setting up RECIST Tumor Response Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="5"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Prepare IRCADb liver CT data
echo "Preparing IRCADb liver CT data..."
export PATIENT_NUM GROUND_TRUTH_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Wait for data preparation
sleep 2

# Get patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

TARGET_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
echo "Using patient: $PATIENT_NUM"
echo "Data directory: $TARGET_DIR"

# Find CT volume (could be DICOM dir or NIfTI)
CT_FILE=""
if [ -f "$TARGET_DIR/ct_volume.nii.gz" ]; then
    CT_FILE="$TARGET_DIR/ct_volume.nii.gz"
elif [ -d "$TARGET_DIR/PATIENT_DICOM" ] && [ "$(ls -1 "$TARGET_DIR/PATIENT_DICOM" 2>/dev/null | wc -l)" -gt 0 ]; then
    CT_FILE="$TARGET_DIR/PATIENT_DICOM"
fi

if [ -z "$CT_FILE" ]; then
    echo "ERROR: No CT data found for patient $PATIENT_NUM"
    ls -la "$TARGET_DIR" 2>/dev/null || echo "Directory does not exist"
    exit 1
fi

echo "CT source: $CT_FILE"

# Verify ground truth exists
GT_FILE="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth not found at $GT_FILE"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Create baseline information file for agent (simulating clinical trial workflow)
echo "Creating baseline measurement reference..."
mkdir -p "$IRCADB_DIR"

python3 << PYEOF
import json
import os

gt_path = "$GT_FILE"
output_dir = "$IRCADB_DIR"

with open(gt_path, 'r') as f:
    gt_data = json.load(f)

# Get tumor measurements from ground truth
tumors = gt_data.get('tumors', [])
if not tumors:
    # Fallback to synthetic measurements if no tumor data
    tumors = [
        {'diameter_mm': 23.0, 'location': 'Liver segment VI'},
        {'diameter_mm': 18.0, 'location': 'Liver segment VIII'},
        {'diameter_mm': 12.0, 'location': 'Liver segment IV'}
    ]

# Create baseline scenario: tumors were larger at baseline (Week 0)
# Simulate ~20% larger baseline (patient showing regression - Stable Disease scenario)
baseline_factor = 1.20

current_measurements = []
baseline_measurements = []

for i, tumor in enumerate(tumors[:3]):
    current_mm = tumor.get('diameter_mm', 15.0 + i * 5)
    baseline_mm = current_mm * baseline_factor
    current_measurements.append(round(current_mm, 1))
    baseline_measurements.append(round(baseline_mm, 1))

# Pad if fewer than 3 tumors
while len(current_measurements) < 3:
    idx = len(current_measurements)
    current_mm = 12.0 + idx * 3
    baseline_mm = current_mm * baseline_factor
    current_measurements.append(round(current_mm, 1))
    baseline_measurements.append(round(baseline_mm, 1))

current_sld = sum(current_measurements)
baseline_sld = sum(baseline_measurements)
percent_change = ((current_sld - baseline_sld) / baseline_sld) * 100

# Determine expected response per RECIST 1.1
if all(m == 0 for m in current_measurements):
    expected_response = "CR"
elif percent_change <= -30:
    expected_response = "PR"
elif percent_change >= 20 and (current_sld - baseline_sld) >= 5:
    expected_response = "PD"
else:
    expected_response = "SD"

# Create baseline info file for agent (visible to agent)
baseline_info = {
    "patient_id": "IRCADb_Patient_${PATIENT_NUM}",
    "scan_type": "Week 12 Follow-up CT",
    "baseline_week": 0,
    "current_week": 12,
    "baseline_lesions": [
        {"id": 1, "location": "Liver segment VI", "diameter_mm": baseline_measurements[0]},
        {"id": 2, "location": "Liver segment VIII", "diameter_mm": baseline_measurements[1]},
        {"id": 3, "location": "Liver segment IV", "diameter_mm": baseline_measurements[2]}
    ],
    "baseline_sld_mm": round(baseline_sld, 1),
    "recist_criteria": {
        "CR": "Disappearance of all target lesions",
        "PR": ">=30% decrease in SLD from baseline",
        "PD": ">=20% increase in SLD AND >=5mm absolute increase",
        "SD": "Neither PR nor PD criteria met"
    },
    "instructions": "Measure each lesion's longest diameter in the axial plane at the slice showing maximum extent. Save measurements and report as specified in the task description."
}

baseline_path = os.path.join(output_dir, "baseline_info.json")
with open(baseline_path, 'w') as f:
    json.dump(baseline_info, f, indent=2)
print(f"Baseline info saved to {baseline_path}")

# Create ground truth for verification (hidden from agent)
gt_verification = {
    "current_measurements_mm": current_measurements,
    "expected_current_sld_mm": round(current_sld, 1),
    "baseline_sld_mm": round(baseline_sld, 1),
    "expected_percent_change": round(percent_change, 2),
    "expected_response": expected_response,
    "tolerance_mm": 5.0,
    "tolerance_percent": 2.0
}

gt_verif_path = os.path.join("$GROUND_TRUTH_DIR", "recist_verification_gt.json")
with open(gt_verif_path, 'w') as f:
    json.dump(gt_verification, f, indent=2)

print(f"Ground truth verification data saved")
print(f"Expected: SLD={current_sld:.1f}mm, Change={percent_change:.1f}%, Response={expected_response}")
print(f"Individual measurements: {current_measurements}")
PYEOF

# Clean up any previous task artifacts
rm -f "$IRCADB_DIR/recist_measurements.mrk.json" 2>/dev/null || true
rm -f "$IRCADB_DIR/recist_report.json" 2>/dev/null || true
rm -f /tmp/recist_task_result.json 2>/dev/null || true

# Record initial state
cat > /tmp/recist_initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "patient_num": "$PATIENT_NUM",
    "measurement_file_exists": false,
    "report_file_exists": false
}
EOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer Python script to load the CT with proper window/level
cat > /tmp/load_ircadb_ct.py << 'PYEOF'
import slicer
import os
import glob

ct_path = os.environ.get("CT_FILE", "")
patient_num = os.environ.get("PATIENT_NUM", "5")

print(f"Loading IRCADb CT scan for patient {patient_num}...")

volume_node = None

# Try to load NIfTI first
if ct_path.endswith('.nii.gz') and os.path.isfile(ct_path):
    print(f"Loading NIfTI: {ct_path}")
    volume_node = slicer.util.loadVolume(ct_path)
# Try DICOM directory
elif os.path.isdir(ct_path):
    print(f"Loading DICOM directory: {ct_path}")
    # Import DICOM
    from DICOMLib import DICOMUtils
    dicomFiles = glob.glob(os.path.join(ct_path, "**", "*"), recursive=True)
    dicomFiles = [f for f in dicomFiles if os.path.isfile(f)]
    if dicomFiles:
        try:
            loadedNodeIDs = DICOMUtils.loadDICOMFiles(dicomFiles[:1])
            if loadedNodeIDs:
                volume_node = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])
        except:
            # Fallback to simple volume load
            volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set abdominal CT window/level for liver visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window optimized for liver lesion detection
        displayNode.SetWindow(350)  # Window width
        displayNode.SetLevel(50)    # Window center
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Center on volume
    bounds = [0] * 6
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
    
    dims = volume_node.GetImageData().GetDimensions()
    print(f"CT loaded successfully")
    print(f"Volume dimensions: {dims}")
    print(f"Window/Level set to 350/50 (liver soft tissue)")
else:
    print("WARNING: Could not load CT volume")
    print(f"Attempted path: {ct_path}")

print("Setup complete - ready for RECIST measurement task")
PYEOF

# Export environment variables for Python script
export CT_FILE PATIENT_NUM

# Launch Slicer with the Python script
echo "Launching 3D Slicer with liver CT..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" PATIENT_NUM="$PATIENT_NUM" /opt/Slicer/Slicer --python-script /tmp/load_ircadb_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/recist_initial.png ga

# Set permissions
chown -R ga:ga "$IRCADB_DIR" 2>/dev/null || true

echo ""
echo "=== RECIST Task Setup Complete ==="
echo ""
echo "TASK: RECIST Tumor Response Assessment"
echo "========================================"
echo ""
echo "Clinical Scenario: You are evaluating a Week 12 follow-up CT scan"
echo "for a patient enrolled in an immunotherapy clinical trial."
echo ""
echo "Baseline measurements (Week 0):"
echo "  - See: ~/Documents/SlicerData/IRCADb/baseline_info.json"
echo ""
echo "Your task:"
echo "  1. Find the 3 target liver lesions (hypodense masses)"
echo "  2. Measure each lesion's longest diameter using Markups ruler"
echo "  3. Calculate current SLD and percent change from baseline"
echo "  4. Determine RECIST response category (CR/PR/SD/PD)"
echo ""
echo "Save outputs to:"
echo "  - Measurements: ~/Documents/SlicerData/IRCADb/recist_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/IRCADb/recist_report.json"
echo ""