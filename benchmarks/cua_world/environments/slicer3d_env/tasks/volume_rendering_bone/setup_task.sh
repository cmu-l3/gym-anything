#!/bin/bash
echo "=== Setting up Volume Rendering Bone Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
CASE_ID="amos_0001"
VOLUME_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Create necessary directories
mkdir -p "$AMOS_DIR"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Remove any pre-existing screenshot to ensure fresh creation
rm -f "$SCREENSHOT_DIR/bone_rendering.png" 2>/dev/null || true

# Record initial state
echo "Recording initial state..."
if [ -f "$SCREENSHOT_DIR/bone_rendering.png" ]; then
    INITIAL_SCREENSHOT_EXISTS="true"
    INITIAL_SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_DIR/bone_rendering.png" 2>/dev/null || echo "0")
else
    INITIAL_SCREENSHOT_EXISTS="false"
    INITIAL_SCREENSHOT_MTIME="0"
fi

cat > /tmp/initial_state.json << EOF
{
    "screenshot_exists": $INITIAL_SCREENSHOT_EXISTS,
    "screenshot_mtime": $INITIAL_SCREENSHOT_MTIME,
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Prepare AMOS data (downloads real data or generates synthetic)
echo "Preparing AMOS abdominal CT data..."
export AMOS_DIR CASE_ID
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Verify data exists
if [ ! -f "$VOLUME_FILE" ]; then
    echo "ERROR: AMOS volume file not found at $VOLUME_FILE"
    echo "Checking AMOS directory contents:"
    ls -la "$AMOS_DIR" 2>/dev/null || echo "Directory not found"
    exit 1
fi

echo "AMOS data ready: $VOLUME_FILE"
VOLUME_SIZE=$(du -h "$VOLUME_FILE" 2>/dev/null | cut -f1 || echo "unknown")
echo "Volume file size: $VOLUME_SIZE"

# Kill any existing Slicer instance for clean start
echo "Ensuring clean Slicer state..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the AMOS volume pre-loaded
echo "Launching 3D Slicer with AMOS CT data..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start Slicer with the volume file as argument
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$VOLUME_FILE' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start and load data..."
sleep 8

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer\|3D Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to fully load
echo "Waiting for volume to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot showing loaded data
echo "Capturing initial state screenshot..."
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
echo "TASK: Apply bone volume rendering to visualize the spine"
echo ""
echo "The abdominal CT scan is loaded in 3D Slicer."
echo "You need to:"
echo "  1. Go to Volume Rendering module"
echo "  2. Enable volume rendering for the loaded volume"
echo "  3. Select a bone visualization preset (e.g., CT-Bones)"
echo "  4. Rotate the 3D view to show the spine clearly"
echo "  5. Save a screenshot to: ~/Documents/SlicerData/Screenshots/bone_rendering.png"
echo ""
echo "Volume file: $VOLUME_FILE"
echo "Output screenshot: $SCREENSHOT_DIR/bone_rendering.png"
echo ""