#!/bin/bash
echo "=== Setting up CT Tissue Calibration Verification Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare AMOS data
echo "Preparing AMOS abdominal CT data..."
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

export AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh

# Get the case ID used
CASE_ID="amos_0001"
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    exit 1
fi
echo "CT file found: $(du -h "$CT_FILE" | cut -f1)"

# Record initial state
rm -f /tmp/ct_calibration_result.json 2>/dev/null || true
rm -f "$AMOS_DIR"/*.mrk.json 2>/dev/null || true
rm -f "$AMOS_DIR"/fiducials*.json 2>/dev/null || true
date +%s > /tmp/task_start_time.txt

# Save case info for verification
echo "$CASE_ID" > /tmp/ct_case_id.txt
echo "$CT_FILE" > /tmp/ct_file_path.txt

# Store expected HU ranges for reference (but agent doesn't see this)
cat > "$GROUND_TRUTH_DIR/hu_reference.json" << 'REFEOF'
{
  "tissue_types": {
    "air": {"min_hu": -1050, "max_hu": -950, "description": "Lung/air space"},
    "fat": {"min_hu": -150, "max_hu": -50, "description": "Subcutaneous fat"},
    "liver": {"min_hu": 30, "max_hu": 80, "description": "Liver parenchyma"},
    "bone": {"min_hu": 300, "max_hu": 1500, "description": "Cortical bone"}
  },
  "note": "Standard Hounsfield unit reference values for QA"
}
REFEOF
chmod 600 "$GROUND_TRUTH_DIR/hu_reference.json"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT volume
echo "Launching 3D Slicer with CT volume..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start Slicer with the CT file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$CT_FILE' > /tmp/slicer_launch.log 2>&1" &

echo "Waiting for 3D Slicer to start and load data..."
sleep 10

# Wait for Slicer window
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for data to load
sleep 5

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Set appropriate window/level for soft tissue CT viewing
# Create a Python script to configure the view
cat > /tmp/configure_ct_view.py << 'PYEOF'
import slicer

# Get the loaded volume
volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volumes:
    vol = volumes[0]
    print(f"Volume loaded: {vol.GetName()}")
    
    # Get display node and set soft tissue window/level
    display = vol.GetDisplayNode()
    if display:
        # Soft tissue window: W=400, L=40
        display.SetAutoWindowLevel(False)
        display.SetWindowLevel(400, 40)
        print("Set window/level for soft tissue viewing (W=400, L=40)")
    
    # Center slice views on the volume
    slicer.util.resetSliceViews()
    print("Slice views reset")
    
    # Go to a mid-axial slice
    layout_manager = slicer.app.layoutManager()
    red_widget = layout_manager.sliceWidget("Red")
    if red_widget:
        red_logic = red_widget.sliceLogic()
        # Get volume bounds
        bounds = [0]*6
        vol.GetBounds(bounds)
        mid_z = (bounds[4] + bounds[5]) / 2
        red_logic.SetSliceOffset(mid_z)
        print(f"Set axial slice to z={mid_z:.1f}")

print("CT view configured for tissue sampling")
PYEOF

# Run configuration script
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/configure_ct_view.py > /tmp/slicer_config.log 2>&1 &
sleep 8

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    sudo -u ga DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "CT Volume: $CT_FILE"
echo "Case ID: $CASE_ID"
echo ""
echo "TASK: Sample Hounsfield units from 4 tissue types and verify calibration"
echo ""
echo "Expected HU ranges:"
echo "  Air:   -1050 to -950 HU (lung/air space)"
echo "  Fat:   -150 to -50 HU (subcutaneous fat)"
echo "  Liver: 30 to 80 HU (liver parenchyma)"
echo "  Bone:  300 to 1500 HU (cortical bone)"
echo ""
echo "For each tissue:"
echo "  1. Navigate to the tissue in axial view"
echo "  2. Check the HU value in Data Probe panel"
echo "  3. Place a fiducial marker (Ctrl+Shift+A or Markups module)"
echo "  4. Name the fiducial with the tissue type (e.g., 'Air_Sample')"
echo ""
echo "Save the scene when done: File > Save Scene"