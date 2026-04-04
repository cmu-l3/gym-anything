#!/bin/bash
echo "=== Setting up Measure Angle Markup Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create exports directory
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "/home/ga/Documents/SlicerData" 2>/dev/null || true

# Clear any previous task outputs
rm -f "$EXPORTS_DIR/angle_measurement.txt" 2>/dev/null || true
rm -f /tmp/angle_task_result.json 2>/dev/null || true

# Record initial state - no angle measurement file should exist
echo "false" > /tmp/initial_angle_file_exists.txt
if [ -f "$EXPORTS_DIR/angle_measurement.txt" ]; then
    echo "true" > /tmp/initial_angle_file_exists.txt
fi

# Ensure sample data exists
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try GitHub first
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Fallback to kitware
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Trying alternative download source..."
        wget -O "$SAMPLE_FILE" --timeout=120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
    echo "ERROR: Could not obtain MRHead sample data"
    exit 1
fi
echo "Sample file verified: $SAMPLE_FILE ($(du -h "$SAMPLE_FILE" | cut -f1))"

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data pre-loaded
echo "Launching 3D Slicer with MRHead data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer\|MRHead" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "3D Slicer window detected (window: $WID)"
            break
        fi
    fi
    sleep 1
done

# Wait additional time for data to fully load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "3D Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || DISPLAY=:1 wmctrl -a "3D Slicer" 2>/dev/null || true
sleep 2

# Navigate to approximately the ventricle level using Python script
echo "Navigating to ventricle level..."
cat > /tmp/navigate_to_ventricles.py << 'PYEOF'
import slicer

# Get the first volume node
volume_nodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
if volume_nodes.GetNumberOfItems() > 0:
    volume_node = volume_nodes.GetItemAsObject(0)
    print(f"Volume loaded: {volume_node.GetName()}")
    
    # Get image dimensions
    dims = volume_node.GetImageData().GetDimensions()
    print(f"Volume dimensions: {dims}")
    
    # Navigate to approximately slice 130 (ventricle level in MRHead)
    # MRHead is typically 256x256x130
    target_slice = int(dims[2] * 0.5)  # Middle of volume, approximately ventricle level
    
    # Set the red slice (axial) to this level
    red_logic = slicer.app.layoutManager().sliceWidget('Red').sliceLogic()
    red_logic.SetSliceOffset(target_slice)
    
    # Center the view
    slicer.util.resetSliceViews()
    
    print(f"Navigated to axial slice approximately {target_slice}")
else:
    print("No volume loaded yet")
PYEOF

# Run the navigation script
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/navigate_to_ventricles.py 2>/dev/null &
sleep 5
pkill -f "navigate_to_ventricles" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial screenshot..."
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
echo "TASK: Create an angle measurement using the Markups Angle tool"
echo ""
echo "Instructions:"
echo "  1. Go to Markups module (Modules > Markups or search)"
echo "  2. Select 'Angle' markup type"
echo "  3. Place 3 control points in the axial view to measure an angle"
echo "  4. Save the angle value to: $EXPORTS_DIR/angle_measurement.txt"
echo ""
echo "Sample data loaded: MRHead.nrrd (brain MRI)"
echo "Output file location: $EXPORTS_DIR/angle_measurement.txt"