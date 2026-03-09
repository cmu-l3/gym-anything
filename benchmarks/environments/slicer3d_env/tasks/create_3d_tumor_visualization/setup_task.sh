#!/bin/bash
echo "=== Setting up Create 3D Tumor Visualization Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/tumor_3d_visualization.png"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$SCREENSHOT_DIR"
chmod -R 755 "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task results
rm -f /tmp/tumor_3d_task_result.json 2>/dev/null || true
rm -f "$EXPECTED_SCREENSHOT" 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial screenshot count
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# ============================================================
# Prepare BraTS data
# ============================================================
echo "Preparing BraTS brain tumor data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using BraTS sample: $SAMPLE_ID"

# Verify MRI data exists
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR MRI file not found at $FLAIR_FILE"
    exit 1
fi
echo "Found FLAIR MRI: $FLAIR_FILE"

# Copy segmentation to user-accessible location for this task
# (Ground truth is normally hidden, but for this task the agent needs to see it)
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
USER_SEG="$BRATS_DIR/tumor_segmentation.nii.gz"

if [ -f "$GT_SEG" ]; then
    cp "$GT_SEG" "$USER_SEG"
    chown ga:ga "$USER_SEG"
    chmod 644 "$USER_SEG"
    echo "Segmentation copied to: $USER_SEG"
else
    echo "WARNING: Ground truth segmentation not found at $GT_SEG"
    # Try alternative location
    ALT_SEG="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_seg.nii.gz"
    if [ -f "$ALT_SEG" ]; then
        cp "$ALT_SEG" "$USER_SEG"
        chown ga:ga "$USER_SEG"
        chmod 644 "$USER_SEG"
        echo "Segmentation copied from alternative location"
    fi
fi

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true

# ============================================================
# Create Python script to load data and segmentation into Slicer
# ============================================================
LOAD_SCRIPT="/tmp/load_brats_for_3d_viz.py"
cat > "$LOAD_SCRIPT" << PYEOF
import slicer
import os

print("=== Loading BraTS data for 3D visualization task ===")

# File paths
flair_path = "$FLAIR_FILE"
seg_path = "$USER_SEG"

# Load FLAIR MRI as background volume
print(f"Loading FLAIR: {flair_path}")
if os.path.exists(flair_path):
    flair_node = slicer.util.loadVolume(flair_path)
    if flair_node:
        flair_node.SetName("BraTS_FLAIR")
        print(f"  Loaded: {flair_node.GetName()}")
    else:
        print("  ERROR: Failed to load FLAIR")
else:
    print(f"  ERROR: File not found: {flair_path}")

# Load segmentation
print(f"Loading segmentation: {seg_path}")
if os.path.exists(seg_path):
    # Load as segmentation node
    seg_node = slicer.util.loadSegmentation(seg_path)
    if seg_node:
        seg_node.SetName("TumorSegmentation")
        print(f"  Loaded: {seg_node.GetName()}")
        
        # IMPORTANT: Ensure 3D visibility is OFF initially
        display_node = seg_node.GetDisplayNode()
        if display_node:
            display_node.SetVisibility3D(False)
            display_node.SetVisibility2D(True)  # Show in 2D slices
            display_node.SetOpacity2DFill(0.5)
            display_node.SetOpacity2DOutline(1.0)
            print("  3D visibility: OFF (agent must enable)")
            print("  2D visibility: ON")
        else:
            print("  WARNING: No display node")
    else:
        print("  ERROR: Failed to load segmentation")
else:
    print(f"  ERROR: File not found: {seg_path}")

# Set up slice views to show the data
print("Setting up views...")
slicer.util.resetSliceViews()

# Center 3D view
threeDWidget = slicer.app.layoutManager().threeDWidget(0)
if threeDWidget:
    threeDView = threeDWidget.threeDView()
    threeDView.resetFocalPoint()
    print("  3D view centered")

# Go to Welcome module (neutral starting point)
slicer.util.selectModule("Welcome")
print("  Module: Welcome")

print("=== Setup complete ===")
print("Task: Enable 3D visualization and save screenshot to:")
print("  ~/Documents/SlicerData/Screenshots/tumor_3d_visualization.png")
PYEOF

chmod 644 "$LOAD_SCRIPT"
chown ga:ga "$LOAD_SCRIPT"

# ============================================================
# Launch 3D Slicer and load data
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with Python script
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script '$LOAD_SCRIPT' > /tmp/slicer_startup.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Additional wait for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    INIT_SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${INIT_SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record initial state
echo "Recording initial state..."
cat > /tmp/task_initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "sample_id": "$SAMPLE_ID",
    "flair_file": "$FLAIR_FILE",
    "segmentation_file": "$USER_SEG",
    "expected_screenshot": "$EXPECTED_SCREENSHOT",
    "initial_screenshot_count": $INITIAL_SCREENSHOT_COUNT
}
EOF

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create 3D Tumor Visualization"
echo ""
echo "Starting state:"
echo "  - BraTS brain MRI (FLAIR) is loaded"
echo "  - Tumor segmentation 'TumorSegmentation' is loaded"
echo "  - Segmentation is visible in 2D slice views (orange overlay)"
echo "  - 3D view is EMPTY (3D visibility is OFF)"
echo ""
echo "Your goal:"
echo "  1. Go to Segment Editor module"
echo "  2. Enable 3D visualization for the tumor"
echo "  3. Rotate 3D view for good visualization"
echo "  4. Save screenshot to: $EXPECTED_SCREENSHOT"
echo ""