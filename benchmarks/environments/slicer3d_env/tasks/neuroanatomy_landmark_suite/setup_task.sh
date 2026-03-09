#!/bin/bash
echo "=== Setting up Neuroanatomy Landmark Documentation Suite Task ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
MRHEAD_FILE="$SAMPLE_DIR/MRHead.nrrd"

# Create directories
mkdir -p "$SAMPLE_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous task outputs
rm -f "$SAMPLE_DIR/neuroanatomy_landmarks.mrk.json" 2>/dev/null || true
rm -f "$SAMPLE_DIR/neuroanatomy_report.json" 2>/dev/null || true
rm -f /tmp/neuroanatomy_task_result.json 2>/dev/null || true

# Check if MRHead exists, download if needed
if [ ! -f "$MRHEAD_FILE" ] || [ "$(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo 0)" -lt 1000000 ]; then
    echo "Downloading MRHead sample data..."
    
    # Try primary source
    curl -L -o "$MRHEAD_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Check if download succeeded
    if [ ! -f "$MRHEAD_FILE" ] || [ "$(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo 0)" -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        curl -L -o "$MRHEAD_FILE" --connect-timeout 30 --max-time 120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null
    fi
fi

# Verify MRHead file exists
if [ ! -f "$MRHEAD_FILE" ] || [ "$(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo 0)" -lt 100000 ]; then
    echo "ERROR: MRHead sample data not available"
    echo "Creating synthetic brain MRI data..."
    
    python3 << 'PYEOF'
import numpy as np
import os

output_path = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
os.makedirs(os.path.dirname(output_path), exist_ok=True)

# Create synthetic brain MRI volume
shape = (256, 256, 130)
data = np.zeros(shape, dtype=np.int16)

# Create brain structure
center = np.array(shape) / 2
Y, X, Z = np.ogrid[:shape[0], :shape[1], :shape[2]]

# Brain parenchyma (ellipsoid)
brain_mask = ((X - center[1])**2 / (90**2) + 
              (Y - center[0])**2 / (100**2) + 
              (Z - center[2])**2 / (55**2)) < 1.0
data[brain_mask] = np.random.normal(600, 50, np.sum(brain_mask)).astype(np.int16)

# Lateral ventricles (butterfly shape)
for side, x_offset in [(-1, -12), (1, 12)]:
    lv_mask = ((X - (center[1] + x_offset))**2 / (8**2) + 
               (Y - (center[0] - 10))**2 / (20**2) + 
               (Z - (center[2] + 5))**2 / (10**2)) < 1.0
    data[lv_mask] = 200  # CSF is dark

# Third ventricle
tv_mask = ((X - center[1])**2 / (3**2) + 
           (Y - (center[0] + 10))**2 / (8**2) + 
           (Z - (center[2]))**2 / (8**2)) < 1.0
data[tv_mask] = 180

# Corpus callosum
for y_pos, z_pos in [(center[0] - 28, center[2] + 8), (center[0] + 38, center[2] + 12)]:
    cc_mask = ((X - center[1])**2 / (25**2) + 
               (Y - y_pos)**2 / (6**2) + 
               (Z - z_pos)**2 / (4**2)) < 1.0
    data[cc_mask] = 900  # White matter is bright

# Pons
pons_mask = ((X - center[1])**2 / (12**2) + 
             (Y - (center[0] + 28))**2 / (8**2) + 
             (Z - (center[2] - 20))**2 / (10**2)) < 1.0
data[pons_mask] = 700

# Write NRRD
header = f"""NRRD0004
type: int16
dimension: 3
space: left-posterior-superior
sizes: {shape[1]} {shape[0]} {shape[2]}
space directions: (1,0,0) (0,1,0) (0,0,1.3)
kinds: domain domain domain
endian: little
encoding: raw
space origin: (-128,-128,-85)

"""

with open(output_path, 'wb') as f:
    f.write(header.encode('ascii'))
    f.write(data.tobytes())

print(f"Created synthetic MRHead.nrrd at {output_path}")
PYEOF
fi

echo "MRHead file: $MRHEAD_FILE ($(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo 0) bytes)"

# Create ground truth JSON with anatomical coordinates for MRHead
# These coordinates are approximate based on typical MRHead anatomy
cat > "$GROUND_TRUTH_DIR/neuroanatomy_gt.json" << 'GTEOF'
{
    "dataset": "MRHead",
    "coordinate_system": "RAS",
    "structures": {
        "lateral_ventricle_frontal_horn_left": {
            "coordinates_ras": [-12.0, 22.0, 12.0],
            "tolerance_mm": 12.0,
            "description": "Center of left lateral ventricle frontal horn"
        },
        "lateral_ventricle_frontal_horn_right": {
            "coordinates_ras": [12.0, 22.0, 12.0],
            "tolerance_mm": 12.0,
            "description": "Center of right lateral ventricle frontal horn"
        },
        "third_ventricle": {
            "coordinates_ras": [0.0, -8.0, 8.0],
            "tolerance_mm": 10.0,
            "measurement_mm": 5.0,
            "measurement_tolerance": 3.0,
            "measurement_type": "width",
            "description": "Center of third ventricle"
        },
        "corpus_callosum_genu": {
            "coordinates_ras": [0.0, 28.0, 12.0],
            "tolerance_mm": 10.0,
            "measurement_mm": 11.0,
            "measurement_tolerance": 4.0,
            "measurement_type": "thickness",
            "description": "Most anterior point of corpus callosum genu"
        },
        "corpus_callosum_splenium": {
            "coordinates_ras": [0.0, -38.0, 16.0],
            "tolerance_mm": 10.0,
            "measurement_mm": 12.0,
            "measurement_tolerance": 4.0,
            "measurement_type": "thickness",
            "description": "Most posterior point of corpus callosum splenium"
        },
        "pineal_gland": {
            "coordinates_ras": [0.0, -28.0, 6.0],
            "tolerance_mm": 8.0,
            "description": "Center of pineal gland"
        },
        "pons": {
            "coordinates_ras": [0.0, -28.0, -24.0],
            "tolerance_mm": 10.0,
            "measurement_mm": 24.0,
            "measurement_tolerance": 5.0,
            "measurement_type": "ap_diameter",
            "description": "Center of pons at mid-pontine level"
        }
    }
}
GTEOF

chmod 600 "$GROUND_TRUTH_DIR/neuroanatomy_gt.json"
echo "Ground truth created (hidden from agent)"

# Create Slicer Python script to load MRHead
cat > /tmp/load_mrhead.py << PYEOF
import slicer
import os

mrhead_path = "$MRHEAD_FILE"

print(f"Loading MRHead MRI volume...")

try:
    volume_node = slicer.util.loadVolume(mrhead_path)
    
    if volume_node:
        volume_node.SetName("MRHead")
        print(f"Volume loaded: {volume_node.GetName()}")
        print(f"Dimensions: {volume_node.GetImageData().GetDimensions()}")
        
        # Set up display - brain window
        displayNode = volume_node.GetDisplayNode()
        if displayNode:
            displayNode.SetAutoWindowLevel(False)
            displayNode.SetWindow(1400)
            displayNode.SetLevel(500)
        
        # Set as background in all slice views
        for color in ["Red", "Green", "Yellow"]:
            compositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
            compositeNode.SetBackgroundVolumeID(volume_node.GetID())
        
        # Reset views
        slicer.util.resetSliceViews()
        
        # Center on data
        bounds = [0]*6
        volume_node.GetBounds(bounds)
        
        for color in ["Red", "Green", "Yellow"]:
            sliceWidget = slicer.app.layoutManager().sliceWidget(color)
            sliceLogic = sliceWidget.sliceLogic()
            sliceNode = sliceLogic.GetSliceNode()
            center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
            
            if color == "Red":  # Axial
                sliceNode.SetSliceOffset(center[2])
            elif color == "Green":  # Coronal
                sliceNode.SetSliceOffset(center[1])
            else:  # Sagittal
                sliceNode.SetSliceOffset(center[0])
        
        print("MRHead loaded successfully - ready for landmark documentation")
    else:
        print("ERROR: Could not load MRHead volume")
        
except Exception as e:
    print(f"ERROR loading MRHead: {e}")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the MRHead
echo "Launching 3D Slicer with MRHead brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_mrhead.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
wait_for_slicer 90
sleep 8

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Ensure focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 5

# Set permissions
chown -R ga:ga "$SAMPLE_DIR" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/neuroanatomy_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Neuroanatomy Landmark Documentation Suite"
echo "================================================"
echo ""
echo "Create educational documentation of 6 brain structures."
echo ""
echo "For each structure:"
echo "  1. Navigate to the structure"
echo "  2. Place a fiducial marker (Markups module)"
echo "  3. Take measurement if specified"
echo "  4. Note the RAS coordinates"
echo ""
echo "Structures:"
echo "  1. Lateral ventricle frontal horn - measure width"
echo "  2. Third ventricle - measure width"
echo "  3. Corpus callosum genu - measure thickness"
echo "  4. Corpus callosum splenium - measure thickness"
echo "  5. Pineal gland - no measurement"
echo "  6. Pons - measure AP diameter"
echo ""
echo "Save outputs to:"
echo "  - Fiducials: ~/Documents/SlicerData/SampleData/neuroanatomy_landmarks.mrk.json"
echo "  - Report: ~/Documents/SlicerData/SampleData/neuroanatomy_report.json"
echo ""