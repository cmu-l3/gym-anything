#!/bin/bash
echo "=== Setting up Tumor SIR Quantification Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

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

# Verify ground truth exists (hidden from agent)
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clean up any previous task outputs
rm -f /tmp/sir_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/sir_rois.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/sir_report.json" 2>/dev/null || true

# Record initial state
cat > /tmp/sir_initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "sample_id": "$SAMPLE_ID",
    "roi_file_existed": false,
    "report_file_existed": false
}
EOF

# Create a Slicer Python script to load all volumes with proper names
cat > /tmp/load_sir_volumes.py << PYEOF
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

print("Loading BraTS MRI volumes for SIR analysis...")
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

# Set up views for ROI placement task
if loaded_nodes:
    # Start with T1_Contrast as background (shows enhancing tumor clearly)
    t1ce_node = None
    flair_node = None
    for node in loaded_nodes:
        if node.GetName() == "T1_Contrast":
            t1ce_node = node
        elif node.GetName() == "FLAIR":
            flair_node = node
    
    background_node = t1ce_node if t1ce_node else loaded_nodes[0]
    
    # Set slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(background_node.GetID())
    
    # Reset views to show the data
    slicer.util.resetSliceViews()
    
    # Center on the data
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        bounds = [0]*6
        background_node.GetBounds(bounds)
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

print("Setup complete - ready for SIR quantification task")
print("")
print("HINT: Use the Markups module to place spherical ROIs.")
print("      The 'ROI' tool creates spherical regions suitable for this task.")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script to load volumes
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_sir_volumes.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/sir_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tumor Signal Intensity Ratio (SIR) Quantification"
echo "========================================================"
echo ""
echo "Four MRI sequences are loaded: FLAIR, T1, T1_Contrast (T1ce), T2"
echo ""
echo "Your goal:"
echo "  1. Place a spherical ROI in the solid enhancing tumor (bright on T1_Contrast)"
echo "  2. Place a second ROI in normal white matter (contralateral hemisphere)"
echo "  3. Measure mean signal intensity in both ROIs across all sequences"
echo "  4. Calculate SIR = Tumor_Signal / WhiteMatter_Signal for each sequence"
echo "  5. Create a JSON report with measurements and interpretation"
echo ""
echo "Save your outputs:"
echo "  - ROI markups: ~/Documents/SlicerData/BraTS/sir_rois.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/sir_report.json"
echo ""
echo "Expected SIR ranges for high-grade glioma:"
echo "  - T1ce SIR: 1.2-3.0 (enhancement indicates BBB breakdown)"
echo "  - T2/FLAIR SIR: 1.5-4.0 (edema/high cellularity)"
echo "  - T1 SIR: ~0.8-1.2 (tumor often slightly hypointense)"
echo ""