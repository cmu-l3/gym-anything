#!/bin/bash
echo "=== Setting up Configure Linked Views Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clear previous task results
rm -f /tmp/linked_views_result.json 2>/dev/null || true
rm -f "$EXPORTS_DIR/linked_views.png" 2>/dev/null || true

# Record initial screenshot state
mkdir -p "$EXPORTS_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$EXPORTS_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using BraTS sample: $SAMPLE_ID"

# Verify all four MRI sequences exist
SEQUENCES=("flair" "t1" "t1ce" "t2")
MISSING_SEQUENCES=""
for seq in "${SEQUENCES[@]}"; do
    SEQ_FILE="$SAMPLE_DIR/${SAMPLE_ID}_${seq}.nii.gz"
    if [ ! -f "$SEQ_FILE" ]; then
        MISSING_SEQUENCES="$MISSING_SEQUENCES $seq"
    else
        echo "  Found: ${SAMPLE_ID}_${seq}.nii.gz"
    fi
done

if [ -n "$MISSING_SEQUENCES" ]; then
    echo "WARNING: Missing sequences:$MISSING_SEQUENCES"
fi

# Record data info for verification
cat > /tmp/brats_data_info.json << EOF
{
    "sample_id": "$SAMPLE_ID",
    "sample_dir": "$SAMPLE_DIR",
    "sequences": ["flair", "t1", "t1ce", "t2"],
    "timestamp": "$(date -Iseconds)"
}
EOF

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load all four volumes
LOAD_SCRIPT="/tmp/load_brats_volumes.py"
cat > "$LOAD_SCRIPT" << PYEOF
import slicer
import os

sample_id = "$SAMPLE_ID"
sample_dir = "$SAMPLE_DIR"
sequences = ["flair", "t1", "t1ce", "t2"]

print(f"Loading BraTS volumes from {sample_dir}")

loaded_volumes = []
for seq in sequences:
    nii_path = os.path.join(sample_dir, f"{sample_id}_{seq}.nii.gz")
    if os.path.exists(nii_path):
        print(f"Loading {seq}...")
        volume_node = slicer.util.loadVolume(nii_path)
        if volume_node:
            # Rename for clarity
            volume_node.SetName(f"{sample_id}_{seq}")
            loaded_volumes.append(volume_node.GetName())
            print(f"  Loaded: {volume_node.GetName()}")
    else:
        print(f"  Not found: {nii_path}")

print(f"Loaded {len(loaded_volumes)} volumes: {loaded_volumes}")

# Set default view to show the FLAIR image
if loaded_volumes:
    # Find FLAIR volume
    flair_node = slicer.util.getNode(f"{sample_id}_flair")
    if flair_node:
        # Set as background in slice views
        for color in ['Red', 'Yellow', 'Green']:
            slice_composite = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
            slice_composite.SetBackgroundVolumeID(flair_node.GetID())
        print("Set FLAIR as default background volume")

# Go to a good slice position (middle of volume)
if loaded_volumes:
    any_vol = slicer.util.getNode(loaded_volumes[0])
    if any_vol:
        bounds = [0]*6
        any_vol.GetBounds(bounds)
        center_z = (bounds[4] + bounds[5]) / 2
        # Set slice position
        for color in ['Red', 'Yellow', 'Green']:
            slice_node = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceNode()
            slice_node.SetSliceOffset(center_z)
        print(f"Set initial slice position to z={center_z:.1f}")

print("Volume loading complete")
PYEOF

chmod 644 "$LOAD_SCRIPT"
chown ga:ga "$LOAD_SCRIPT"

# Launch Slicer with the loading script
echo "Launching 3D Slicer and loading BraTS volumes..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script $LOAD_SCRIPT > /tmp/slicer_launch.log 2>&1" &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for volumes to load
echo "Waiting for volumes to load..."
sleep 15

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo "BraTS sample: $SAMPLE_ID"
echo "Available sequences: FLAIR, T1, T1ce, T2"
echo ""
echo "TASK: Set up a dual-view layout with linked scrolling"
echo "  1. Change layout to Compare or Side-by-Side"
echo "  2. Assign different sequences to left/right views"
echo "  3. Enable view linking"
echo "  4. Save screenshot to ~/Documents/SlicerData/Exports/linked_views.png"