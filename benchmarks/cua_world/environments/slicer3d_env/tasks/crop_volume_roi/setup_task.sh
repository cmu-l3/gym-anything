#!/bin/bash
echo "=== Setting up Crop Volume ROI Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure sample data directory exists
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Download sample data if not present
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    wget -q -O "$SAMPLE_FILE" \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    curl -L -o "$SAMPLE_FILE" \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "ERROR: Sample file not found at $SAMPLE_FILE"
    exit 1
fi

SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
echo "Sample file: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"

# Record initial state - check if output file already exists
OUTPUT_PATH="/home/ga/Documents/SlicerData/Exports/MRHead_cropped.nrrd"
INITIAL_OUTPUT_EXISTS="false"
INITIAL_OUTPUT_SIZE="0"
INITIAL_OUTPUT_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_OUTPUT_EXISTS="true"
    INITIAL_OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    echo "WARNING: Output file already exists (will check if modified during task)"
fi

# Save initial state for verification
cat > /tmp/crop_initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "sample_file": "$SAMPLE_FILE",
    "sample_size": $SAMPLE_SIZE,
    "output_path": "$OUTPUT_PATH",
    "initial_output_exists": $INITIAL_OUTPUT_EXISTS,
    "initial_output_size": $INITIAL_OUTPUT_SIZE,
    "initial_output_mtime": $INITIAL_OUTPUT_MTIME
}
EOF

chmod 666 /tmp/crop_initial_state.json 2>/dev/null || true

# Get original volume dimensions
echo "Analyzing original volume dimensions..."
python3 << 'PYEOF'
import json
import os
try:
    import nibabel as nib
    nii = nib.load("/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd")
    dims = list(nii.shape)
    voxels = int(dims[0] * dims[1] * dims[2]) if len(dims) >= 3 else 0
    info = {
        "original_dimensions": dims[:3] if len(dims) >= 3 else dims,
        "original_voxel_count": voxels
    }
    with open("/tmp/original_volume_info.json", "w") as f:
        json.dump(info, f)
    print(f"Original dimensions: {dims[:3] if len(dims) >= 3 else dims}")
    print(f"Original voxel count: {voxels}")
except Exception as e:
    # Try with nrrd library instead
    try:
        import nrrd
        data, header = nrrd.read("/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd")
        dims = list(data.shape)
        voxels = int(dims[0] * dims[1] * dims[2]) if len(dims) >= 3 else 0
        info = {
            "original_dimensions": dims[:3] if len(dims) >= 3 else dims,
            "original_voxel_count": voxels
        }
        with open("/tmp/original_volume_info.json", "w") as f:
            json.dump(info, f)
        print(f"Original dimensions: {dims[:3] if len(dims) >= 3 else dims}")
    except Exception as e2:
        print(f"Could not analyze volume: {e}, {e2}")
        # Use approximate known dimensions
        info = {
            "original_dimensions": [256, 256, 130],
            "original_voxel_count": 256 * 256 * 130
        }
        with open("/tmp/original_volume_info.json", "w") as f:
            json.dump(info, f)
PYEOF

chmod 666 /tmp/original_volume_info.json 2>/dev/null || true

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data loaded
echo "Launching 3D Slicer with MRHead loaded..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Create a Python script to load the data
cat > /tmp/load_mrhead.py << 'LOADPY'
import slicer
# Load MRHead
slicer.util.loadVolume("/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd")
# Reset view to show the data
slicer.util.resetSliceViews()
LOADPY

# Launch Slicer with the load script
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_mrhead.py > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in $(seq 1 60); do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        # Check for window
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Wait for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/crop_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "MRHead brain MRI is loaded in 3D Slicer."
echo ""
echo "TASK: Crop the volume to remove empty background space."
echo ""
echo "Instructions:"
echo "1. Go to Modules > Converters > Crop Volume (or search 'Crop Volume')"
echo "2. Create an ROI that tightly encloses the brain"
echo "3. Click 'Apply' to create the cropped volume"
echo "4. Save cropped volume to: ~/Documents/SlicerData/Exports/MRHead_cropped.nrrd"
echo ""