#!/bin/bash
echo "=== Setting up Four-Panel MRI Comparison Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
SAMPLE_ID="BraTS2021_00000"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Record initial screenshot count
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# Clean previous task files
rm -f /tmp/fourpanel_task_result.json 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/four_panel_comparison.png" 2>/dev/null || true

echo "Preparing BraTS brain tumor data..."

# Prepare BraTS data (uses the shared preparation script)
export SAMPLE_ID GROUND_TRUTH_DIR BRATS_DIR
/workspace/scripts/prepare_brats_data.sh "$SAMPLE_ID"

# Get actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi
echo "$SAMPLE_ID" > /tmp/task_sample_id.txt

CASE_DIR="$BRATS_DIR/$SAMPLE_ID"

# Verify all 4 sequences exist
SEQUENCES=("t1" "t1ce" "t2" "flair")
MISSING=0
for seq in "${SEQUENCES[@]}"; do
    SEQ_FILE="$CASE_DIR/${SAMPLE_ID}_${seq}.nii.gz"
    if [ ! -f "$SEQ_FILE" ]; then
        echo "ERROR: Missing $seq sequence: $SEQ_FILE"
        MISSING=$((MISSING + 1))
    else
        echo "Found: ${SAMPLE_ID}_${seq}.nii.gz ($(du -h "$SEQ_FILE" | cut -f1))"
    fi
done

if [ "$MISSING" -gt 0 ]; then
    echo "ERROR: $MISSING sequences missing, cannot proceed"
    exit 1
fi

echo ""
echo "=== Launching 3D Slicer with all sequences ==="

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load all 4 volumes
LOAD_SCRIPT="/tmp/load_brats_volumes.py"
cat > "$LOAD_SCRIPT" << PYEOF
import slicer
import os

sample_id = "$SAMPLE_ID"
case_dir = "$CASE_DIR"

sequences = ["t1", "t1ce", "t2", "flair"]

print(f"Loading BraTS data from {case_dir}")

for seq in sequences:
    filepath = os.path.join(case_dir, f"{sample_id}_{seq}.nii.gz")
    if os.path.exists(filepath):
        print(f"Loading {seq}...")
        node = slicer.util.loadVolume(filepath)
        # Rename node for clarity
        node.SetName(f"{sample_id}_{seq}")
        print(f"  Loaded: {node.GetName()}")
    else:
        print(f"  ERROR: File not found: {filepath}")

# Show the first volume in slice views
volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volumes:
    first_vol = volumes[0]
    slicer.util.setSliceViewerLayers(background=first_vol)
    print(f"Set {first_vol.GetName()} as background")

print(f"Loaded {volumes.GetNumberOfItems()} volumes total")
PYEOF

chmod 644 "$LOAD_SCRIPT"
chown ga:ga "$LOAD_SCRIPT"

# Launch Slicer and load volumes
echo "Starting 3D Slicer..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start Slicer with the loading script
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script '$LOAD_SCRIPT' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for Slicer to start and load data..."
sleep 10

# Wait for Slicer window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for volumes to load
echo "Waiting for volumes to finish loading..."
sleep 15

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Verify volumes are loaded by checking scene
echo "Verifying loaded volumes..."
VERIFY_SCRIPT="/tmp/verify_volumes.py"
cat > "$VERIFY_SCRIPT" << 'PYEOF'
import slicer
volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
count = volumes.GetNumberOfItems()
print(f"VOLUME_COUNT={count}")
for i in range(count):
    node = volumes.GetItemAsObject(i)
    print(f"  Volume {i+1}: {node.GetName()}")
PYEOF

# Run verification (non-blocking)
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-code 'exec(open(\"/tmp/verify_volumes.py\").read())' --no-main-window" > /tmp/verify_volumes.log 2>&1 &
sleep 5
pkill -f "verify_volumes" 2>/dev/null || true

if [ -f /tmp/verify_volumes.log ]; then
    VOLUME_COUNT=$(grep "VOLUME_COUNT=" /tmp/verify_volumes.log | cut -d'=' -f2 || echo "0")
    echo "Volumes loaded: $VOLUME_COUNT"
    cat /tmp/verify_volumes.log
fi

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create a four-panel comparison view showing all four MRI sequences"
echo ""
echo "Loaded volumes:"
echo "  - ${SAMPLE_ID}_t1 (T1-weighted)"
echo "  - ${SAMPLE_ID}_t1ce (T1 contrast-enhanced)"
echo "  - ${SAMPLE_ID}_t2 (T2-weighted)"
echo "  - ${SAMPLE_ID}_flair (FLAIR)"
echo ""
echo "Steps:"
echo "  1. Change layout to Four-Up (View > Layout > Four-Up)"
echo "  2. Assign a different sequence to each panel"
echo "  3. Ensure views are linked"
echo "  4. Navigate to slice showing tumor (around slice 70-90)"
echo "  5. Save screenshot to: $SCREENSHOT_DIR/four_panel_comparison.png"
echo ""