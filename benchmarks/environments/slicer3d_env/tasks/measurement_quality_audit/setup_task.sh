#!/bin/bash
echo "=== Setting up Measurement Quality Audit Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare AMOS data (downloads real data or creates synthetic)
echo "Preparing abdominal CT data..."
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the actual case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Clean previous outputs
rm -f "$AMOS_DIR/corrected_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/measurement_audit_report.json" 2>/dev/null || true

# Create erroneous trainee measurements
echo "Creating pre-placed trainee measurements with deliberate errors..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
case_id = os.environ.get("CASE_ID", "amos_0001")

# Load CT and get spacing info
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata()
spacing = ct_nii.header.get_zooms()[:3]
affine = ct_nii.affine

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# Load ground truth if available
gt_path = os.path.join(gt_dir, f"{case_id}_aorta_gt.json")
if os.path.exists(gt_path):
    with open(gt_path, 'r') as f:
        gt_info = json.load(f)
else:
    # Use defaults based on synthetic data properties
    gt_info = {
        "max_diameter_mm": 33.0,
        "max_diameter_slice": 45,
        "aorta_center_voxels": [128, 153, 45]
    }

# Get dimensions
nx, ny, nz = ct_data.shape
center_x, center_y = nx // 2, ny // 2

# Aorta location (from GT or estimate)
aorta_cx = gt_info.get("aorta_center_voxels", [128, 153, 45])[0]
aorta_cy = gt_info.get("aorta_center_voxels", [128, 153, 45])[1]
max_diam_slice = gt_info.get("max_diameter_slice", 45)
max_diam_mm = gt_info.get("max_diameter_mm", 33.0)

# Helper to convert voxel to RAS coordinates
def voxel_to_ras(voxel_coords):
    voxel_homog = np.array([voxel_coords[0], voxel_coords[1], voxel_coords[2], 1])
    ras = affine @ voxel_homog
    return [float(x) for x in ras[:3]]

# ============================================================
# Create ERRONEOUS measurement 1: Aortic diameter at wrong level
# Should be at max_diam_slice (~L2-L3) but placed 40 slices higher
# Also made oblique instead of perpendicular
# ============================================================
wrong_slice = min(nz - 5, max_diam_slice + 40)  # 40 slices too high
oblique_offset = 8  # voxels to make it oblique

# Wrong diameter measurement - oblique line at wrong level
error1_p1 = voxel_to_ras([aorta_cx - 15 - oblique_offset, aorta_cy, wrong_slice])
error1_p2 = voxel_to_ras([aorta_cx + 15 + oblique_offset, aorta_cy + oblique_offset, wrong_slice])

# Correct location for comparison
correct1_p1 = voxel_to_ras([aorta_cx - 17, aorta_cy, max_diam_slice])
correct1_p2 = voxel_to_ras([aorta_cx + 17, aorta_cy, max_diam_slice])

# ============================================================
# Create CORRECT measurement 2: IVC diameter
# Placed at L2 level, perpendicular to vessel
# ============================================================
ivc_cx = aorta_cx  # IVC is typically to the right of aorta
ivc_cy = aorta_cy + 30  # and slightly posterior
ivc_slice = max_diam_slice + 5

correct2_p1 = voxel_to_ras([ivc_cx - 10, ivc_cy, ivc_slice])
correct2_p2 = voxel_to_ras([ivc_cx + 10, ivc_cy, ivc_slice])

# ============================================================
# Create ERRONEOUS measurement 3: Celiac axis origin distance
# Should measure from celiac trunk origin, but placed 20 voxels off
# ============================================================
celiac_slice = max_diam_slice + 25  # celiac is superior to renal
celiac_offset_error = 20  # voxels off in the wrong direction

# Wrong endpoint placement
error3_p1 = voxel_to_ras([aorta_cx, aorta_cy - celiac_offset_error, celiac_slice])
error3_p2 = voxel_to_ras([aorta_cx + 40, aorta_cy, celiac_slice - 10])

# Correct would be at actual celiac origin
correct3_p1 = voxel_to_ras([aorta_cx, aorta_cy, celiac_slice])

# ============================================================
# Create CORRECT measurement 4: Renal artery to bifurcation distance
# ============================================================
renal_slice = max_diam_slice + 10  # renal arteries at ~L1-L2
bifurc_slice = max(5, max_diam_slice - 30)  # bifurcation at ~L4

correct4_p1 = voxel_to_ras([aorta_cx, aorta_cy, renal_slice])
correct4_p2 = voxel_to_ras([aorta_cx, aorta_cy, bifurc_slice])

# ============================================================
# Create Slicer markup JSON (MRML Markups JSON format)
# ============================================================
markup_data = {
    "@schema": "https://raw.githubusercontent.com/slicer/slicer/master/Modules/Loadable/Markups/Resources/Schema/markups-schema-v1.0.3.json#",
    "markups": [
        {
            "type": "Line",
            "coordinateSystem": "LPS",
            "coordinateUnits": "mm",
            "locked": False,
            "fixedNumberOfControlPoints": True,
            "labelFormat": "%N-%d",
            "lastUsedControlPointNumber": 2,
            "name": "trainee_aorta_diameter",
            "controlPoints": [
                {"id": "1", "label": "1", "description": "", "position": error1_p1, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"},
                {"id": "2", "label": "2", "description": "", "position": error1_p2, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"}
            ],
            "measurements": [{"enabled": True, "name": "length", "units": "mm"}],
            "display": {"visibility": True, "opacity": 1.0, "color": [1.0, 0.0, 0.0], "selectedColor": [1.0, 0.5, 0.5], "propertiesLabelVisibility": True, "pointLabelsVisibility": False, "textScale": 3.0, "lineThickness": 0.2, "lineColorFadingStart": 1.0, "lineColorFadingEnd": 10.0}
        },
        {
            "type": "Line",
            "coordinateSystem": "LPS",
            "coordinateUnits": "mm",
            "locked": False,
            "fixedNumberOfControlPoints": True,
            "labelFormat": "%N-%d",
            "lastUsedControlPointNumber": 2,
            "name": "trainee_ivc_diameter",
            "controlPoints": [
                {"id": "1", "label": "1", "description": "", "position": correct2_p1, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"},
                {"id": "2", "label": "2", "description": "", "position": correct2_p2, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"}
            ],
            "measurements": [{"enabled": True, "name": "length", "units": "mm"}],
            "display": {"visibility": True, "opacity": 1.0, "color": [0.0, 1.0, 0.0], "selectedColor": [0.5, 1.0, 0.5], "propertiesLabelVisibility": True, "pointLabelsVisibility": False, "textScale": 3.0, "lineThickness": 0.2}
        },
        {
            "type": "Line",
            "coordinateSystem": "LPS",
            "coordinateUnits": "mm",
            "locked": False,
            "fixedNumberOfControlPoints": True,
            "labelFormat": "%N-%d",
            "lastUsedControlPointNumber": 2,
            "name": "trainee_celiac_distance",
            "controlPoints": [
                {"id": "1", "label": "1", "description": "", "position": error3_p1, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"},
                {"id": "2", "label": "2", "description": "", "position": error3_p2, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"}
            ],
            "measurements": [{"enabled": True, "name": "length", "units": "mm"}],
            "display": {"visibility": True, "opacity": 1.0, "color": [1.0, 0.5, 0.0], "selectedColor": [1.0, 0.75, 0.5], "propertiesLabelVisibility": True, "pointLabelsVisibility": False, "textScale": 3.0, "lineThickness": 0.2}
        },
        {
            "type": "Line",
            "coordinateSystem": "LPS",
            "coordinateUnits": "mm",
            "locked": False,
            "fixedNumberOfControlPoints": True,
            "labelFormat": "%N-%d",
            "lastUsedControlPointNumber": 2,
            "name": "trainee_renal_bifurcation",
            "controlPoints": [
                {"id": "1", "label": "1", "description": "", "position": correct4_p1, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"},
                {"id": "2", "label": "2", "description": "", "position": correct4_p2, "orientation": [-1.0, -0.0, -0.0, -0.0, -1.0, -0.0, 0.0, 0.0, 1.0], "selected": True, "locked": False, "visibility": True, "positionStatus": "defined"}
            ],
            "measurements": [{"enabled": True, "name": "length", "units": "mm"}],
            "display": {"visibility": True, "opacity": 1.0, "color": [0.0, 0.5, 1.0], "selectedColor": [0.5, 0.75, 1.0], "propertiesLabelVisibility": True, "pointLabelsVisibility": False, "textScale": 3.0, "lineThickness": 0.2}
        }
    ]
}

# Save trainee measurements
trainee_markup_path = os.path.join(amos_dir, "trainee_measurements.mrk.json")
with open(trainee_markup_path, 'w') as f:
    json.dump(markup_data, f, indent=2)
print(f"Trainee measurements saved to {trainee_markup_path}")

# ============================================================
# Save ground truth for verification
# ============================================================
verification_gt = {
    "erroneous_measurements": ["trainee_aorta_diameter", "trainee_celiac_distance"],
    "correct_measurements": ["trainee_ivc_diameter", "trainee_renal_bifurcation"],
    "errors": {
        "trainee_aorta_diameter": {
            "error_type": "wrong_level_and_oblique",
            "description": "Measurement placed at wrong vertebral level (too cranial) and line is oblique rather than perpendicular to vessel axis",
            "wrong_slice": int(wrong_slice),
            "correct_slice": int(max_diam_slice),
            "slice_error_mm": float((wrong_slice - max_diam_slice) * spacing[2]),
            "correct_diameter_mm": float(max_diam_mm),
            "correct_p1_ras": correct1_p1,
            "correct_p2_ras": correct1_p2
        },
        "trainee_celiac_distance": {
            "error_type": "wrong_landmarks",
            "description": "Measurement endpoints not at correct anatomical landmarks - proximal point offset from true celiac trunk origin",
            "offset_error_mm": float(celiac_offset_error * spacing[1]),
            "correct_proximal_ras": correct3_p1
        }
    },
    "correct_aorta_measurement": {
        "p1_ras": correct1_p1,
        "p2_ras": correct1_p2,
        "diameter_mm": float(max_diam_mm),
        "slice_index": int(max_diam_slice),
        "vertebral_level": "L2-L3"
    },
    "spacing_mm": [float(s) for s in spacing],
    "volume_shape": list(ct_data.shape),
    "case_id": case_id
}

gt_verify_path = os.path.join(gt_dir, f"{case_id}_measurement_audit_gt.json")
with open(gt_verify_path, 'w') as f:
    json.dump(verification_gt, f, indent=2)
print(f"Verification ground truth saved to {gt_verify_path}")

# Set permissions
os.chmod(trainee_markup_path, 0o644)
print("Setup complete")
PYEOF

# Set proper permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Kill any existing Slicer
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load data and markups in Slicer
cat > /tmp/load_audit_task.py << 'SLICERPY'
import slicer
import os

amos_dir = "/home/ga/Documents/SlicerData/AMOS"
case_id = "amos_0001"

# Check for actual case ID
if os.path.exists("/tmp/amos_case_id"):
    with open("/tmp/amos_case_id", "r") as f:
        case_id = f.read().strip()

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
markup_path = os.path.join(amos_dir, "trainee_measurements.mrk.json")

# Load CT volume
if os.path.exists(ct_path):
    volumeNode = slicer.util.loadVolume(ct_path)
    if volumeNode:
        volumeNode.SetName("AbdominalCT")
        # Set appropriate window/level for abdominal CT
        displayNode = volumeNode.GetDisplayNode()
        if displayNode:
            displayNode.SetAutoWindowLevel(False)
            displayNode.SetWindow(400)
            displayNode.SetLevel(40)
        print(f"Loaded CT: {ct_path}")
else:
    print(f"WARNING: CT not found at {ct_path}")

# Load trainee measurements
if os.path.exists(markup_path):
    success = slicer.util.loadMarkups(markup_path)
    if success:
        print(f"Loaded trainee measurements: {markup_path}")
        # List loaded markups
        lineNodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
        print(f"Found {len(lineNodes)} line markup(s):")
        for node in lineNodes:
            print(f"  - {node.GetName()}")
    else:
        print(f"Failed to load markups from {markup_path}")
else:
    print(f"WARNING: Markups not found at {markup_path}")

# Switch to conventional layout with all views
slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)

# Fit all slice views
for sliceViewName in ["Red", "Yellow", "Green"]:
    sliceWidget = slicer.app.layoutManager().sliceWidget(sliceViewName)
    if sliceWidget:
        sliceWidget.sliceController().fitSliceToBackground()

print("\n=== Audit task setup complete ===")
print("Review the trainee measurements in the Markups module")
print("Some measurements have technical errors that need correction")
SLICERPY

# Launch Slicer with the setup script
echo "Launching 3D Slicer with audit task data..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_audit_task.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
sleep 10
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null && DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer started successfully"
        break
    fi
    sleep 2
done

# Maximize Slicer window
sleep 5
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Measurement Quality Audit Task Setup Complete ==="
echo ""
echo "TASK: Review the pre-placed trainee measurements for technical errors"
echo ""
echo "Four measurements have been placed by a trainee:"
echo "  1. trainee_aorta_diameter - Aortic diameter"
echo "  2. trainee_ivc_diameter - IVC diameter"
echo "  3. trainee_celiac_distance - Celiac axis distance"
echo "  4. trainee_renal_bifurcation - Renal to bifurcation distance"
echo ""
echo "Some measurements have ERRORS. You must:"
echo "  - Identify which measurements are technically incorrect"
echo "  - Create corrected versions (prefix with 'corrected_')"
echo "  - Save corrected markups to: ~/Documents/SlicerData/AMOS/corrected_measurements.mrk.json"
echo "  - Create audit report at: ~/Documents/SlicerData/AMOS/measurement_audit_report.json"
echo ""