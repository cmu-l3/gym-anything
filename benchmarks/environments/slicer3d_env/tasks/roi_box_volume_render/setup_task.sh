#!/bin/bash
echo "=== Setting up ROI Box Volume Rendering Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
AMOS_FILE="$AMOS_DIR/amos_0001.nii.gz"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded"

# Clear any previous task outputs
rm -f "$EXPORTS_DIR/roi_kidney_render.png" 2>/dev/null || true
rm -f /tmp/roi_task_result.json 2>/dev/null || true

# Prepare AMOS abdominal CT data
echo "Preparing AMOS abdominal CT data..."
export AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh amos_0001

# Verify data exists
if [ ! -f "$AMOS_FILE" ]; then
    echo "ERROR: AMOS data file not found at $AMOS_FILE"
    exit 1
fi

echo "AMOS data file found: $(du -h "$AMOS_FILE" | cut -f1)"

# Create ground truth for verification (kidney location info)
echo "Creating ground truth reference..."
python3 << 'PYEOF'
import json
import os

gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

# Reference values for right kidney ROI (based on synthetic AMOS data)
# In RAS coordinates
ground_truth = {
    "right_kidney_approx_center_ras": [65, -10, 0],
    "right_kidney_approx_size_mm": [50, 45, 90],
    "acceptable_roi_center": {
        "R": {"min": 30, "max": 110},
        "A": {"min": -60, "max": 40},
        "S": {"min": -60, "max": 80}
    },
    "acceptable_roi_size": {
        "min_per_axis": 40,
        "max_per_axis": 160
    },
    "notes": "Right kidney is on patient's right (positive R in RAS)"
}

gt_path = os.path.join(gt_dir, "roi_kidney_gt.json")
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load data and enable volume rendering
SETUP_SCRIPT="/tmp/setup_roi_task.py"
cat > "$SETUP_SCRIPT" << 'PYEOF'
import slicer
import os

# Load AMOS volume
amos_file = "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz"
print(f"Loading volume: {amos_file}")

try:
    volumeNode = slicer.util.loadVolume(amos_file)
    print(f"Volume loaded: {volumeNode.GetName()}")
except Exception as e:
    print(f"Error loading volume: {e}")
    raise

# Enable volume rendering
print("Setting up volume rendering...")
volRenLogic = slicer.modules.volumerendering.logic()
displayNode = volRenLogic.CreateDefaultVolumeRenderingNodes(volumeNode)

if displayNode:
    displayNode.SetVisibility(True)
    print("Volume rendering enabled")
    
    # Use CT-AAA preset for abdominal visualization
    presets = volRenLogic.GetPresetsScene()
    presetNode = None
    for i in range(presets.GetNumberOfNodes()):
        node = presets.GetNthNode(i)
        name = node.GetName() if hasattr(node, 'GetName') else ""
        if "CT-AAA" in name or "CT-Cardiac" in name or "CT-Bone" in name:
            presetNode = node
            break
    
    if presetNode:
        displayNode.GetVolumePropertyNode().Copy(presetNode)
        print(f"Applied preset: {presetNode.GetName()}")
else:
    print("Warning: Could not create volume rendering display node")

# Reset 3D view
layoutManager = slicer.app.layoutManager()
threeDWidget = layoutManager.threeDWidget(0)
threeDView = threeDWidget.threeDView()
threeDView.resetFocalPoint()
threeDView.resetCamera()

print("Setup complete - volume rendering should be visible")
PYEOF

chmod 644 "$SETUP_SCRIPT"
chown ga:ga "$SETUP_SCRIPT"

# Launch Slicer with setup script
echo "Launching 3D Slicer with volume rendering..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script '$SETUP_SCRIPT' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for Slicer to start..."
sleep 10

for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for volume rendering to initialize
echo "Waiting for volume rendering to initialize..."
sleep 15

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/roi_task_initial.png ga
sleep 1

if [ -f /tmp/roi_task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/roi_task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create an ROI box around the right kidney and configure"
echo "      volume rendering to show only the cropped region."
echo ""
echo "The abdominal CT is loaded with volume rendering enabled."
echo "You should see the full anatomy (spine, organs) in 3D view."
echo ""
echo "Steps:"
echo "  1. Create ROI box in Markups module"
echo "  2. Position around right kidney (patient's right = left side of screen)"
echo "  3. In Volume Rendering module, enable ROI cropping"
echo "  4. Save screenshot to: ~/Documents/SlicerData/Exports/roi_kidney_render.png"
echo ""