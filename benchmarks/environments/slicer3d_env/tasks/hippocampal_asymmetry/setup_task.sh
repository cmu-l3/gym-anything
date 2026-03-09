#!/bin/bash
echo "=== Setting up Hippocampal Volume Asymmetry Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"

# Verify required files exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t2.nii.gz"
    "${SAMPLE_ID}_flair.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Record initial state - clean up any previous outputs
rm -f /tmp/hippocampal_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/hippocampal_segmentation.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/hippocampal_report.json" 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Create anatomical reference data for hippocampus location verification
# These are approximate normalized coordinates for hippocampus in BraTS data
# The hippocampus is in the medial temporal lobe
cat > /tmp/hippocampal_reference.json << 'REFEOF'
{
    "description": "Hippocampal anatomical reference bounds",
    "notes": "Hippocampus is in medial temporal lobe, adjacent to temporal horn of lateral ventricle",
    "expected_location": {
        "left": {
            "hemisphere": "left",
            "region": "medial_temporal",
            "relative_x_range": [0.2, 0.45],
            "relative_y_range": [0.35, 0.65],
            "relative_z_range": [0.25, 0.50]
        },
        "right": {
            "hemisphere": "right",
            "region": "medial_temporal",
            "relative_x_range": [0.55, 0.8],
            "relative_y_range": [0.35, 0.65],
            "relative_z_range": [0.25, 0.50]
        }
    },
    "volume_reference": {
        "normal_range_ml": [2.5, 4.5],
        "acceptable_range_ml": [1.5, 6.0],
        "typical_asymmetry_percent": 5.0
    },
    "clinical_classification": {
        "normal": {"hai_max": 10},
        "borderline": {"hai_min": 10, "hai_max": 15},
        "significant": {"hai_min": 15}
    }
}
REFEOF

# Copy reference to ground truth dir
mkdir -p "$GROUND_TRUTH_DIR"
cp /tmp/hippocampal_reference.json "$GROUND_TRUTH_DIR/hippocampal_reference.json"
chmod 600 "$GROUND_TRUTH_DIR/hippocampal_reference.json"

# Create a Slicer Python script to load volumes for hippocampal assessment
cat > /tmp/load_hippocampal_task.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Load T1, T2, and FLAIR - T1 is best for hippocampus visualization
volumes = [
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t2.nii.gz", "T2"),
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
]

print("Loading brain MRI volumes for hippocampal assessment...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"    Loaded: {node.GetName()}")
        else:
            print(f"    ERROR loading {filepath}")

print(f"Loaded {len(loaded_nodes)} volumes")

if loaded_nodes:
    # Use T1 as primary (best for gray/white matter differentiation)
    t1_node = None
    for node in loaded_nodes:
        if node.GetName() == "T1":
            t1_node = node
            break
    if not t1_node:
        t1_node = loaded_nodes[0]
    
    # Set T1 as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(t1_node.GetID())
    
    # Get image bounds for centering
    bounds = [0]*6
    t1_node.GetBounds(bounds)
    
    # Calculate center and temporal lobe region
    center_x = (bounds[0] + bounds[1]) / 2
    center_y = (bounds[2] + bounds[3]) / 2
    center_z = (bounds[4] + bounds[5]) / 2
    
    # Position views to show temporal lobe region (slightly inferior and posterior)
    # Red = Axial, Green = Coronal, Yellow = Sagittal
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        if color == "Red":  # Axial - show inferior brain where hippocampus is
            # Position at ~40% from bottom (temporal lobe level)
            z_offset = bounds[4] + (bounds[5] - bounds[4]) * 0.4
            sliceNode.SetSliceOffset(z_offset)
        elif color == "Green":  # Coronal - best for hippocampus visualization
            # Position at ~50% (mid brain)
            y_offset = bounds[2] + (bounds[3] - bounds[2]) * 0.5
            sliceNode.SetSliceOffset(y_offset)
        else:  # Yellow = Sagittal
            # Position slightly off midline to show hippocampus
            x_offset = center_x - (bounds[1] - bounds[0]) * 0.15
            sliceNode.SetSliceOffset(x_offset)
    
    # Set conventional layout (four-up or conventional)
    slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    # Reset slice views
    slicer.util.resetSliceViews()
    
    print(f"Views positioned for hippocampal assessment")
    print(f"  - Coronal view (Green) is best for hippocampus visualization")
    print(f"  - Hippocampus is in medial temporal lobe, near temporal horn of ventricle")

print("Setup complete - ready for hippocampal segmentation task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with brain MRI volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_hippocampal_task.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
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

# Wait for volumes to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/hippocampal_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Hippocampal Volume Asymmetry Assessment"
echo "=============================================="
echo ""
echo "You are given brain MRI sequences (T1, T2, FLAIR)."
echo "Assess hippocampal volume asymmetry for epilepsy/dementia evaluation."
echo ""
echo "Your goal:"
echo "  1. Navigate to temporal lobe region (coronal view is best)"
echo "  2. Identify bilateral hippocampi (medial temporal lobe)"
echo "  3. Create segments named 'Left_Hippocampus' and 'Right_Hippocampus'"
echo "  4. Calculate volumes using Segment Statistics"
echo "  5. Compute Asymmetry Index: HAI = |L-R|/((L+R)/2) × 100"
echo "  6. Classify: Normal (<10%), Borderline (10-15%), Significant (>15%)"
echo ""
echo "Anatomical tips:"
echo "  - Hippocampus is in medial temporal lobe"
echo "  - Adjacent to temporal horn of lateral ventricle"
echo "  - Curved/seahorse shape in coronal view"
echo "  - Normal volume: 2.5-4.5 mL per side"
echo ""
echo "Save outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/BraTS/hippocampal_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/BraTS/hippocampal_report.json"
echo ""