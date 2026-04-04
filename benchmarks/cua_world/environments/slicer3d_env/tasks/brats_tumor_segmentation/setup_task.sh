#!/bin/bash
echo "=== Setting up Brain Tumor Segmentation Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used (may differ from default if specified case not found)
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"

echo "Using sample: $SAMPLE_ID"

# Verify all required files exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
    "${SAMPLE_ID}_t2.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Verify ground truth exists (but don't tell the agent)
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state
rm -f /tmp/brats_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/agent_segmentation.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_report.txt" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create a Slicer Python script to load all volumes with proper names
cat > /tmp/load_brats_volumes.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Define volumes to load with display names
volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("Loading BraTS MRI volumes...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name} from {filepath}")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"    Loaded: {node.GetName()}")
        else:
            print(f"    ERROR loading {filepath}")
    else:
        print(f"  WARNING: File not found: {filepath}")

print(f"Loaded {len(loaded_nodes)} volumes")

# Set up the views for brain tumor segmentation
if loaded_nodes:
    # Make FLAIR the background volume (good for seeing edema)
    flair_node = slicer.util.getNode("FLAIR") if slicer.util.getNode("FLAIR") else loaded_nodes[0]

    # Set slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())

    # Reset views to show the data
    slicer.util.resetSliceViews()

    # Center on the data
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        bounds = [0]*6
        flair_node.GetBounds(bounds)
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        sliceNode.SetSliceOffset(center[2] if color == "Red" else center[1] if color == "Green" else center[0])

print("Setup complete - ready for segmentation task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script to load volumes
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_volumes.py > /tmp/slicer_launch.log 2>&1 &

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

# Wait for volumes to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/brats_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Tumor Segmentation"
echo "==============================="
echo ""
echo "You are given a brain MRI scan of a patient with a glioma (brain tumor)."
echo "Four MRI sequences are loaded: FLAIR, T1, T1_Contrast, and T2."
echo ""
echo "Your goal:"
echo "  1. Identify and segment the complete tumor region"
echo "  2. Create a 3D visualization of the tumor"
echo "  3. Report the tumor volume in milliliters (mL)"
echo ""
echo "Clinical context:"
echo "  - The FLAIR sequence highlights edema (swelling) around the tumor"
echo "  - The T1_Contrast sequence shows the enhancing (active) tumor with bright signal"
echo "  - The tumor may have multiple components: enhancing core, non-enhancing core, and surrounding edema"
echo ""
echo "Save your outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/BraTS/agent_segmentation.nii.gz"
echo "  - Volume report: ~/Documents/SlicerData/BraTS/tumor_report.txt"
echo ""
