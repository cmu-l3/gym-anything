#!/bin/bash
set -e
echo "=== Setting up Evans Index Calculation Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source utility functions
source /workspace/scripts/task_utils.sh

# Prepare BraTS data
echo "Preparing BraTS brain MRI data..."
bash /workspace/scripts/prepare_brats_data.sh

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"

# Verify FLAIR file exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    echo "Available files in BraTS directory:"
    find "$BRATS_DIR" -name "*.nii.gz" 2>/dev/null | head -20
    exit 1
fi

echo "Using FLAIR image: $FLAIR_FILE"

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create output directories
mkdir -p /home/ga/Documents/SlicerData/Screenshots
mkdir -p /home/ga/Documents/SlicerData/Exports
chown -R ga:ga /home/ga/Documents/SlicerData

# Clean up any previous task artifacts
rm -f /home/ga/Documents/SlicerData/Exports/evans_measurements.mrk.json 2>/dev/null || true
rm -f /home/ga/Documents/SlicerData/Exports/evans_*.json 2>/dev/null || true
rm -f /home/ga/Documents/SlicerData/Screenshots/evans_*.png 2>/dev/null || true
rm -f /tmp/evans_result.json 2>/dev/null || true
rm -f /tmp/evans_measurements.json 2>/dev/null || true

# Record initial state - count existing line markups (should be 0)
echo "0" > /tmp/initial_line_count.txt

# Save task info for verification
cat > /tmp/evans_task_info.json << INFOJSON
{
    "sample_id": "$SAMPLE_ID",
    "flair_file": "$FLAIR_FILE",
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "brats_dir": "$BRATS_DIR",
    "expected_output_dir": "/home/ga/Documents/SlicerData/Exports"
}
INFOJSON

# Create Slicer Python script to set up the scene
SETUP_SCRIPT="/tmp/setup_evans_task.py"
cat > "$SETUP_SCRIPT" << 'PYSETUP'
import slicer
import os
import sys

# Get the FLAIR file path from environment
flair_path = os.environ.get("FLAIR_FILE", "")

print(f"Setup script starting...")
print(f"FLAIR path: {flair_path}")

if flair_path and os.path.exists(flair_path):
    print(f"Loading FLAIR volume: {flair_path}")
    
    try:
        # Load the FLAIR volume
        volume_node = slicer.util.loadVolume(flair_path)
        
        if volume_node:
            print(f"Volume loaded successfully: {volume_node.GetName()}")
            
            # Set up the layout - four-up view with axial prominent
            layoutManager = slicer.app.layoutManager()
            layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)
            
            # Get the red slice (axial) widget
            red_widget = layoutManager.sliceWidget("Red")
            red_logic = red_widget.sliceLogic()
            red_node = red_logic.GetSliceNode()
            
            # Set axial orientation
            red_node.SetOrientationToAxial()
            
            # Fit the volume to the slice views
            slicer.util.resetSliceViews()
            
            # Get volume bounds to navigate to frontal horn level
            bounds = [0] * 6
            volume_node.GetBounds(bounds)
            z_min, z_max = bounds[4], bounds[5]
            z_range = z_max - z_min
            
            # Navigate to approximately 55-65% of the way up from bottom
            # This is typically where frontal horns are widest
            target_z = z_min + z_range * 0.60
            red_node.SetSliceOffset(target_z)
            
            print(f"Volume bounds Z: {z_min:.1f} to {z_max:.1f}")
            print(f"Navigated to Z offset: {target_z:.1f}")
            
            # Set appropriate window/level for brain FLAIR MRI
            display_node = volume_node.GetDisplayNode()
            if display_node:
                # Auto window/level first, then slightly adjust
                display_node.AutoWindowLevelOn()
                slicer.app.processEvents()
                display_node.AutoWindowLevelOff()
                
                # Get current values and adjust for better contrast
                window = display_node.GetWindow()
                level = display_node.GetLevel()
                # Slightly increase contrast
                display_node.SetWindow(window * 0.9)
                display_node.SetLevel(level)
                print(f"Window/Level set: {display_node.GetWindow():.0f}/{display_node.GetLevel():.0f}")
            
            # Switch to Markups module so user can create measurements
            slicer.util.selectModule("Markups")
            
            print("=" * 50)
            print("SETUP COMPLETE")
            print("=" * 50)
            print("Task: Calculate Evans Index")
            print("1. Navigate to find maximum frontal horn width")
            print("2. Create LINE markup across frontal horns")
            print("3. Create LINE markup across skull at same level")
            print("Evans Index = Frontal Horn Width / Skull Width")
            print("=" * 50)
        else:
            print("ERROR: Failed to load volume - node is None")
            sys.exit(1)
    except Exception as e:
        print(f"ERROR loading volume: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
else:
    print(f"ERROR: FLAIR file not found or not specified")
    print(f"Path checked: {flair_path}")
    sys.exit(1)
PYSETUP

chmod 644 "$SETUP_SCRIPT"

# Launch Slicer with the setup script
echo "Launching 3D Slicer with FLAIR volume..."
export FLAIR_FILE="$FLAIR_FILE"
sudo -u ga DISPLAY=:1 FLAIR_FILE="$FLAIR_FILE" /opt/Slicer/Slicer --python-script "$SETUP_SCRIPT" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Additional wait for module loading and volume rendering
sleep 15

# Maximize and focus window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    echo "Slicer window maximized and focused (ID: $SLICER_WID)"
else
    echo "Warning: Could not find Slicer window ID"
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png ga
echo "Initial screenshot saved to /tmp/task_initial_state.png"

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    INIT_SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot size: $INIT_SIZE bytes"
fi

echo ""
echo "=== Evans Index Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "FLAIR file: $FLAIR_FILE"
echo ""
echo "INSTRUCTIONS:"
echo "  1. Navigate axial slices to find maximum frontal horn width"
echo "  2. Switch to Markups module and create a Line"
echo "  3. Draw horizontal line across frontal horns (bright CSF spaces)"
echo "  4. Create second line across internal skull diameter at SAME level"
echo "  5. Evans Index = Frontal Horn Width / Skull Width"
echo "  6. Save/export measurements or take screenshot"
echo ""
echo "Normal Evans Index < 0.30"
echo "Ventriculomegaly (hydrocephalus) if Evans Index >= 0.30"