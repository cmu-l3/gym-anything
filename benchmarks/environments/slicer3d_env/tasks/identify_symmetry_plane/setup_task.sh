#!/bin/bash
echo "=== Setting up Identify Midsagittal Symmetry Plane task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Set up directories
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

mkdir -p "$SAMPLE_DIR"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Ensure sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found, downloading MRHead..."
    # Try multiple sources
    wget -q -O "$SAMPLE_FILE" \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget -q -O "$SAMPLE_FILE" \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
    echo "WARNING: Could not download sample data"
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file exists: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
else
    echo "ERROR: Sample file not found at $SAMPLE_FILE"
fi

# Record initial state - count existing screenshots and markups
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# Record initial screenshot state for comparison
ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null > /tmp/initial_screenshots_list.txt || true

# Clean previous task results
rm -f /tmp/symmetry_plane_result.json 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/midsagittal_plane.png" 2>/dev/null || true

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data
echo "Launching 3D Slicer with MRHead sample data..."

# Ensure X server access
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Slicer with the MRHead file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer\|MRHead"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Verify Slicer is running
if pgrep -f "Slicer" > /dev/null; then
    echo "3D Slicer is running"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer PID: $SLICER_PID"
else
    echo "WARNING: Slicer may not have started properly"
fi

# Record volume information for ground truth verification
python3 << 'PYEOF'
import os
import json

# We'll compute expected plane parameters based on MRHead volume
# MRHead is a standard brain MRI - the midsagittal plane should:
# - Have normal approximately [1, 0, 0] (L-R axis in RAS)
# - Pass through the center of the volume

# MRHead typical properties (from Slicer sample data)
# These are approximate for verification purposes
ground_truth = {
    "expected_plane_normal": [1.0, 0.0, 0.0],  # L-R axis
    "expected_plane_normal_tolerance_deg": 15,
    "expected_center_lr": 0.0,  # Approximate center in RAS
    "position_tolerance_mm": 10,
    "volume_name_pattern": "MRHead",
    "notes": "MRHead is an RAS-oriented brain MRI with origin near center"
}

gt_path = "/tmp/midsagittal_ground_truth.json"
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth reference saved to {gt_path}")
PYEOF

# Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c%s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Identify and place the midsagittal symmetry plane"
echo ""
echo "Instructions:"
echo "  1. Examine the brain MRI in the slice views"
echo "  2. Go to Markups module and create a Plane markup"
echo "  3. Position the plane along the midsagittal (midline) of the brain"
echo "  4. Rename the plane to include 'Midsagittal' in the name"
echo "  5. Save a screenshot to: ~/Documents/SlicerData/Screenshots/midsagittal_plane.png"
echo ""
echo "Sample data: $SAMPLE_FILE"
echo "Screenshot output: $SCREENSHOT_DIR/midsagittal_plane.png"