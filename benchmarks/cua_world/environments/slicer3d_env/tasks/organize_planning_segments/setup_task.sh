#!/bin/bash
echo "=== Setting up Organize Planning Segments Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
INPUT_SCENE="$IRCADB_DIR/planning_scene.mrb"
OUTPUT_SCENE="$IRCADB_DIR/organized_planning.mrb"

# Create directories
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga "/home/ga/Documents/SlicerData" 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Remove any previous output to ensure clean state
rm -f "$OUTPUT_SCENE" 2>/dev/null || true
rm -f /tmp/segment_task_result.json 2>/dev/null || true

# ============================================================
# Prepare IRCADb data if not already available
# ============================================================
echo "Preparing liver CT data..."
export IRCADB_DIR GROUND_TRUTH_DIR

# Run IRCADb data preparation (downloads real data or creates synthetic)
/workspace/scripts/prepare_ircadb_data.sh 5 2>/dev/null || {
    echo "IRCADb preparation script not found or failed, creating synthetic data..."
}

# ============================================================
# Create the planning scene with generic segment names
# ============================================================
echo "Creating planning scene with generic segment names..."

python3 << 'PYEOF'
import os
import sys
import json

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

ircadb_dir = "/home/ga/Documents/SlicerData/IRCADb"
gt_dir = "/var/lib/slicer/ground_truth"

# Check if we have real segmentation data
seg_path = os.path.join(gt_dir, "ircadb_patient5_seg.nii.gz")
ct_path = None

# Find CT volume
for fname in os.listdir(ircadb_dir):
    if fname.endswith('.nii.gz') and 'seg' not in fname.lower():
        ct_path = os.path.join(ircadb_dir, fname)
        break

# If no real data, create synthetic for testing
if not os.path.exists(seg_path) or ct_path is None:
    print("Creating synthetic liver planning data...")
    
    # Create synthetic CT volume
    np.random.seed(42)
    nx, ny, nz = 128, 128, 80
    spacing = (1.5, 1.5, 3.0)
    
    affine = np.eye(4)
    affine[0, 0] = spacing[0]
    affine[1, 1] = spacing[1]
    affine[2, 2] = spacing[2]
    
    # CT-like volume with structures
    ct_data = np.random.normal(40, 10, (nx, ny, nz)).astype(np.int16)
    
    # Create body outline
    Y, X = np.ogrid[:nx, :ny]
    cx, cy = nx // 2, ny // 2
    body_mask = ((X - cx)**2 / (50**2) + (Y - cy)**2 / (40**2)) <= 1.0
    
    for z in range(nz):
        ct_data[:, :, z][~body_mask] = -1000
    
    ct_path = os.path.join(ircadb_dir, "liver_ct.nii.gz")
    ct_nii = nib.Nifti1Image(ct_data, affine)
    nib.save(ct_nii, ct_path)
    
    # Create segmentation with 4 structures
    seg_data = np.zeros((nx, ny, nz), dtype=np.int16)
    
    # Liver (label 1) - large ellipsoid
    liver_cx, liver_cy = cx - 10, cy
    for z in range(20, 65):
        for x in range(nx):
            for y in range(ny):
                dist = ((x - liver_cx)**2 / (35**2) + 
                       (y - liver_cy)**2 / (30**2) + 
                       ((z - 42)**2) / (22**2))
                if dist <= 1.0 and body_mask[x, y]:
                    seg_data[x, y, z] = 1
    
    # Tumor (label 2) - small sphere inside liver
    tumor_cx, tumor_cy, tumor_cz = liver_cx + 15, liver_cy - 10, 45
    for x in range(nx):
        for y in range(ny):
            for z in range(nz):
                dist = np.sqrt((x - tumor_cx)**2 + (y - tumor_cy)**2 + (z - tumor_cz)**2)
                if dist <= 8:
                    seg_data[x, y, z] = 2
    
    # Portal vein (label 3) - cylinder through liver
    pv_cx, pv_cy = liver_cx - 5, liver_cy + 5
    for z in range(25, 60):
        for x in range(nx):
            for y in range(ny):
                dist = np.sqrt((x - pv_cx)**2 + (y - pv_cy)**2)
                if dist <= 4 and seg_data[x, y, z] == 1:
                    seg_data[x, y, z] = 3
    
    # Hepatic vein (label 4) - another vessel
    hv_cx, hv_cy = liver_cx + 5, liver_cy - 5
    for z in range(30, 55):
        for x in range(nx):
            for y in range(ny):
                dist = np.sqrt((x - hv_cx)**2 + (y - hv_cy)**2)
                if dist <= 3 and seg_data[x, y, z] == 1:
                    seg_data[x, y, z] = 4
    
    seg_path = os.path.join(gt_dir, "ircadb_patient5_seg.nii.gz")
    os.makedirs(gt_dir, exist_ok=True)
    seg_nii = nib.Nifti1Image(seg_data, affine)
    nib.save(seg_nii, seg_path)
    
    print(f"Created synthetic CT: {ct_path}")
    print(f"Created synthetic segmentation: {seg_path}")
else:
    print(f"Using existing data: {ct_path}, {seg_path}")

# Save paths for Slicer scene creation
with open("/tmp/planning_data_paths.json", "w") as f:
    json.dump({
        "ct_path": ct_path,
        "seg_path": seg_path
    }, f)

print("Data preparation complete")
PYEOF

# ============================================================
# Create Slicer scene with generic segment names
# ============================================================
echo "Creating Slicer scene with generic segments..."

# Create Python script to build the scene
cat > /tmp/create_planning_scene.py << 'SLICERPY'
import slicer
import os
import json

# Load data paths
with open("/tmp/planning_data_paths.json", "r") as f:
    paths = json.load(f)

ct_path = paths["ct_path"]
seg_path = paths["seg_path"]

print(f"Loading CT from: {ct_path}")
print(f"Loading segmentation from: {seg_path}")

# Clear the scene
slicer.mrmlScene.Clear(0)

# Load the CT volume
if os.path.exists(ct_path):
    volumeNode = slicer.util.loadVolume(ct_path)
    if volumeNode:
        volumeNode.SetName("LiverCT")
        print(f"Loaded volume: {volumeNode.GetName()}")

# Load the segmentation
if os.path.exists(seg_path):
    # Load as labelmap first, then convert to segmentation
    labelmapNode = slicer.util.loadLabelVolume(seg_path)
    if labelmapNode:
        labelmapNode.SetName("TempLabelmap")
        
        # Create segmentation node
        segmentationNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
        segmentationNode.SetName("LiverSegmentation")
        
        # Import labelmap to segmentation
        slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmapNode, segmentationNode)
        
        # Remove temporary labelmap
        slicer.mrmlScene.RemoveNode(labelmapNode)
        
        # Rename segments to generic names with default gray colors
        segmentation = segmentationNode.GetSegmentation()
        
        # Map label values to generic names
        segment_mapping = {
            0: None,  # Background
            1: ("Segment_1", (0.5, 0.5, 0.5)),  # Liver -> gray
            2: ("Segment_2", (0.6, 0.6, 0.6)),  # Tumor -> gray
            3: ("Segment_3", (0.4, 0.4, 0.4)),  # Portal vein -> gray
            4: ("Segment_4", (0.55, 0.55, 0.55))  # Hepatic vein -> gray
        }
        
        # Rename each segment
        num_segments = segmentation.GetNumberOfSegments()
        print(f"Number of segments: {num_segments}")
        
        for i in range(num_segments):
            segment_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segment_id)
            if segment:
                original_name = segment.GetName()
                # Determine which label this is based on index
                label_idx = i + 1
                if label_idx in segment_mapping and segment_mapping[label_idx]:
                    new_name, color = segment_mapping[label_idx]
                    segment.SetName(new_name)
                    segment.SetColor(color[0], color[1], color[2])
                    print(f"Renamed '{original_name}' to '{new_name}' with gray color")
        
        print("Segmentation created with generic names")

# Set up 3D view
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Show segmentation in 3D
if segmentationNode:
    segmentationNode.CreateClosedSurfaceRepresentation()

# Save the scene
output_path = "/home/ga/Documents/SlicerData/IRCADb/planning_scene.mrb"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
slicer.util.saveScene(output_path)
print(f"Scene saved to: {output_path}")

# Verify the scene was saved
if os.path.exists(output_path):
    size_kb = os.path.getsize(output_path) / 1024
    print(f"Scene file size: {size_kb:.1f} KB")
else:
    print("ERROR: Scene file was not saved!")
SLICERPY

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Run the scene creation script in Slicer
echo "Running Slicer to create scene..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/create_planning_scene.py > /tmp/slicer_scene_create.log 2>&1 &
SLICER_PID=$!

# Wait for scene creation (max 60 seconds)
for i in $(seq 1 60); do
    if [ -f "$INPUT_SCENE" ]; then
        SIZE=$(stat -c%s "$INPUT_SCENE" 2>/dev/null || echo "0")
        if [ "$SIZE" -gt 10000 ]; then
            echo "Scene created successfully (${SIZE} bytes)"
            break
        fi
    fi
    sleep 2
done

# Kill the scene creation Slicer instance
kill $SLICER_PID 2>/dev/null || true
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Verify scene was created
if [ ! -f "$INPUT_SCENE" ]; then
    echo "ERROR: Failed to create planning scene!"
    exit 1
fi

echo "Input scene: $INPUT_SCENE ($(stat -c%s "$INPUT_SCENE") bytes)"

# ============================================================
# Save ground truth expected segment info
# ============================================================
cat > "$GROUND_TRUTH_DIR/expected_segments.json" << 'GTEOF'
{
    "expected_segments": {
        "Liver Parenchyma": {"r": 166, "g": 128, "b": 91, "original": "Segment_1"},
        "Tumor": {"r": 241, "g": 214, "b": 69, "original": "Segment_2"},
        "Portal Vein": {"r": 56, "g": 77, "b": 186, "original": "Segment_3"},
        "Hepatic Vein": {"r": 128, "g": 48, "b": 166, "original": "Segment_4"}
    },
    "color_tolerance": 15,
    "required_segment_count": 4
}
GTEOF

chmod 600 "$GROUND_TRUTH_DIR/expected_segments.json"

# ============================================================
# Launch Slicer with the planning scene
# ============================================================
echo "Launching 3D Slicer with planning scene..."

# Launch Slicer with the scene
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$INPUT_SCENE" > /tmp/slicer_task.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to load..."
wait_for_slicer 90

# Maximize and focus
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Organize the surgical planning segments"
echo ""
echo "Current segment names (to be renamed):"
echo "  - Segment_1 → Liver Parenchyma (Brown: 166, 128, 91)"
echo "  - Segment_2 → Tumor (Yellow: 241, 214, 69)"
echo "  - Segment_3 → Portal Vein (Blue: 56, 77, 186)"
echo "  - Segment_4 → Hepatic Vein (Purple: 128, 48, 166)"
echo ""
echo "Save the organized scene to: $OUTPUT_SCENE"
echo ""