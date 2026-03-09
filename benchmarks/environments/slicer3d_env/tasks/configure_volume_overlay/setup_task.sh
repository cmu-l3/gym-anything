#!/bin/bash
echo "=== Setting up Configure Volume Overlay Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Remove any previous output files
rm -f "$EXPORTS_DIR/overlay_result.png" 2>/dev/null || true
rm -f /tmp/overlay_task_result.json 2>/dev/null || true

# Record initial state
echo "false" > /tmp/initial_overlay_configured.txt

# ============================================================
# Prepare BraTS data
# ============================================================
echo "Preparing BraTS brain tumor data..."
export BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using BraTS sample: $SAMPLE_ID"

# Verify required files exist
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
T1CE_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz"

if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    ls -la "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || ls -la "$BRATS_DIR/" 2>/dev/null
    exit 1
fi

if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    exit 1
fi

echo "Found FLAIR: $FLAIR_FILE"
echo "Found T1ce: $T1CE_FILE"

# Save file paths for later reference
echo "$FLAIR_FILE" > /tmp/flair_path.txt
echo "$T1CE_FILE" > /tmp/t1ce_path.txt
echo "$SAMPLE_ID" > /tmp/overlay_sample_id.txt

# ============================================================
# Launch 3D Slicer and load both volumes
# ============================================================
echo "Launching 3D Slicer with BraTS volumes..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load both volumes
cat > /tmp/load_brats_volumes.py << PYEOF
import slicer
import time

print("Loading BraTS volumes for overlay task...")

# Load FLAIR volume
flair_path = "$FLAIR_FILE"
print(f"Loading FLAIR from: {flair_path}")
flair_node = slicer.util.loadVolume(flair_path)
if flair_node:
    flair_node.SetName("FLAIR")
    print(f"FLAIR loaded: {flair_node.GetName()}")
else:
    print("ERROR: Failed to load FLAIR")

# Load T1ce volume
t1ce_path = "$T1CE_FILE"
print(f"Loading T1ce from: {t1ce_path}")
t1ce_node = slicer.util.loadVolume(t1ce_path)
if t1ce_node:
    t1ce_node.SetName("T1ce")
    print(f"T1ce loaded: {t1ce_node.GetName()}")
else:
    print("ERROR: Failed to load T1ce")

# Verify both volumes are loaded
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
print(f"Total volumes loaded: {volume_nodes.GetNumberOfItems()}")

# Set FLAIR as background initially (default single volume display)
# Do NOT configure foreground - that's the task!
slicer.util.setSliceViewerLayers(background=flair_node)

print("Initial setup complete - FLAIR shown as background only")
print("Task: Configure T1ce as foreground overlay with ~50% opacity")
PYEOF

chmod 644 /tmp/load_brats_volumes.py
chown ga:ga /tmp/load_brats_volumes.py

# Launch Slicer
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start Slicer with Python script
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_volumes.py > /tmp/slicer_overlay.log 2>&1" &

echo "Waiting for Slicer to start and load data..."
sleep 15

# Wait for Slicer window
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for data to fully load
sleep 10

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# ============================================================
# Record initial slice composite state
# ============================================================
echo "Recording initial slice composite state..."

cat > /tmp/record_initial_state.py << 'PYEOF'
import slicer
import json

initial_state = {
    "volumes_loaded": 0,
    "flair_loaded": False,
    "t1ce_loaded": False,
    "composite_states": []
}

# Check loaded volumes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
initial_state["volumes_loaded"] = volume_nodes.GetNumberOfItems()

for i in range(volume_nodes.GetNumberOfItems()):
    node = volume_nodes.GetItemAsObject(i)
    name = node.GetName().lower()
    if "flair" in name:
        initial_state["flair_loaded"] = True
    if "t1ce" in name or "t1_ce" in name or "t1-ce" in name:
        initial_state["t1ce_loaded"] = True

# Record slice composite node states
composite_nodes = slicer.util.getNodesByClass("vtkMRMLSliceCompositeNode")
for i in range(composite_nodes.GetNumberOfItems()):
    node = composite_nodes.GetItemAsObject(i)
    state = {
        "name": node.GetName(),
        "background_id": node.GetBackgroundVolumeID() or "",
        "foreground_id": node.GetForegroundVolumeID() or "",
        "foreground_opacity": node.GetForegroundOpacity()
    }
    initial_state["composite_states"].append(state)

with open("/tmp/initial_composite_state.json", "w") as f:
    json.dump(initial_state, f, indent=2)

print(f"Initial state recorded: {json.dumps(initial_state, indent=2)}")
PYEOF

# Run the state recording script
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/record_initial_state.py" > /tmp/record_state.log 2>&1 &
sleep 8
pkill -f "record_initial_state" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/overlay_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/overlay_initial.png 2>/dev/null || true

if [ -f /tmp/overlay_initial.png ]; then
    SIZE=$(stat -c %s /tmp/overlay_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
echo ""
echo "TASK: Configure volume overlay in 3D Slicer"
echo ""
echo "Loaded volumes:"
echo "  - FLAIR (currently shown as background)"
echo "  - T1ce (available but not configured as overlay)"
echo ""
echo "Your task:"
echo "  1. Set FLAIR as Background layer"
echo "  2. Set T1ce as Foreground layer"
echo "  3. Set Foreground Opacity to ~50%"
echo "  4. Save screenshot to: $EXPORTS_DIR/overlay_result.png"
echo ""
echo "Hint: Click the pin icon in slice view corner to access layer controls"