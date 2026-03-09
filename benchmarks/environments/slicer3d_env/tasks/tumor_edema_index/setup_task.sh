#!/bin/bash
echo "=== Setting up Brain Tumor Edema Index Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure data directories exist
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

CASE_DIR="$BRATS_DIR/$SAMPLE_ID"

echo "Using BraTS sample: $SAMPLE_ID"

# Verify MRI files exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
    "${SAMPLE_ID}_t2.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$CASE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $CASE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Copy the ground truth segmentation to the working directory as the "pre-existing" segmentation
# (This simulates an AI-generated segmentation that the agent needs to analyze)
SEG_SOURCE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
SEG_DEST="$BRATS_DIR/tumor_segmentation.nii.gz"

if [ -f "$SEG_SOURCE" ]; then
    cp "$SEG_SOURCE" "$SEG_DEST"
    chown ga:ga "$SEG_DEST" 2>/dev/null || true
    chmod 644 "$SEG_DEST" 2>/dev/null || true
    echo "Copied segmentation to $SEG_DEST"
else
    echo "ERROR: Ground truth segmentation not found at $SEG_SOURCE!"
    exit 1
fi

# Calculate and save ground truth values for verification
echo "Calculating ground truth edema index..."
python3 << PYEOF
import json
import os
import sys
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
seg_path = "$SEG_DEST"

print(f"Loading segmentation from: {seg_path}")

# Load segmentation
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
voxel_dims = seg_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel dimensions (mm): {voxel_dims}")
print(f"Voxel volume (ml): {voxel_volume_ml:.6f}")

# Calculate volumes for each label
# BraTS labels: 1=necrotic, 2=edema, 4=enhancing
necrotic_voxels = int(np.sum(seg_data == 1))
edema_voxels = int(np.sum(seg_data == 2))
enhancing_voxels = int(np.sum(seg_data == 4))

print(f"Necrotic voxels (label 1): {necrotic_voxels}")
print(f"Edema voxels (label 2): {edema_voxels}")
print(f"Enhancing voxels (label 4): {enhancing_voxels}")

# Calculate volumes in mL
necrotic_volume_ml = float(necrotic_voxels * voxel_volume_ml)
edema_volume_ml = float(edema_voxels * voxel_volume_ml)
enhancing_volume_ml = float(enhancing_voxels * voxel_volume_ml)

# Core = necrotic + enhancing
core_volume_ml = necrotic_volume_ml + enhancing_volume_ml

print(f"Edema volume: {edema_volume_ml:.2f} mL")
print(f"Core volume (necrotic + enhancing): {core_volume_ml:.2f} mL")

# Calculate PEI
if core_volume_ml > 0:
    pei_ratio = edema_volume_ml / core_volume_ml
else:
    pei_ratio = 0.0

print(f"PEI ratio: {pei_ratio:.3f}")

# Determine prognostic class
if pei_ratio < 2.0:
    prognostic_class = "Low"
elif pei_ratio <= 4.0:
    prognostic_class = "Moderate"
else:
    prognostic_class = "High"

print(f"Prognostic class: {prognostic_class}")

# Save ground truth for verification
gt_data = {
    "patient_id": sample_id,
    "edema_volume_ml": round(edema_volume_ml, 3),
    "core_volume_ml": round(core_volume_ml, 3),
    "necrotic_volume_ml": round(necrotic_volume_ml, 3),
    "enhancing_volume_ml": round(enhancing_volume_ml, 3),
    "pei_ratio": round(pei_ratio, 4),
    "prognostic_class": prognostic_class,
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "voxel_volume_ml": voxel_volume_ml,
    "necrotic_voxels": necrotic_voxels,
    "edema_voxels": edema_voxels,
    "enhancing_voxels": enhancing_voxels
}

gt_path = os.path.join(gt_dir, f"{sample_id}_edema_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
PYEOF

# Verify ground truth was saved
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_edema_gt.json" ]; then
    echo "ERROR: Failed to create ground truth file!"
    exit 1
fi

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true

# Remove any previous agent output
rm -f "$BRATS_DIR/edema_analysis_report.json" 2>/dev/null || true

# Save sample ID for export script
echo "$SAMPLE_ID" > /tmp/edema_task_sample_id.txt

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load all data into Slicer
LOAD_SCRIPT="/tmp/load_edema_task.py"
cat > "$LOAD_SCRIPT" << 'LOADEOF'
import slicer
import os
import sys

# Get environment variables
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
case_dir = os.environ.get("CASE_DIR", "/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")

print(f"Loading BraTS data for sample: {sample_id}")
print(f"Case directory: {case_dir}")
print(f"BraTS directory: {brats_dir}")

# Load MRI sequences
sequences = [
    ('flair', 'FLAIR'),
    ('t1', 'T1'),
    ('t1ce', 'T1_Contrast'),
    ('t2', 'T2')
]

loaded_volumes = []
for seq_name, display_name in sequences:
    filepath = os.path.join(case_dir, f"{sample_id}_{seq_name}.nii.gz")
    if os.path.exists(filepath):
        print(f"Loading {display_name} from {filepath}")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_volumes.append(node)
            print(f"  Loaded: {node.GetName()}")
        else:
            print(f"  ERROR: Could not load {filepath}")
    else:
        print(f"  WARNING: File not found: {filepath}")

print(f"Loaded {len(loaded_volumes)} MRI volumes")

# Load the segmentation
seg_path = os.path.join(brats_dir, "tumor_segmentation.nii.gz")
if os.path.exists(seg_path):
    print(f"Loading segmentation from {seg_path}")
    segNode = slicer.util.loadSegmentation(seg_path)
    if segNode:
        segNode.SetName("TumorSegmentation")
        segmentation = segNode.GetSegmentation()
        num_segments = segmentation.GetNumberOfSegments()
        print(f"Loaded segmentation with {num_segments} segments")
        
        # Try to set more descriptive segment names
        for i in range(num_segments):
            segment_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segment_id)
            current_name = segment.GetName()
            print(f"  Segment {i}: {current_name} (ID: {segment_id})")
    else:
        print("ERROR: Could not load segmentation")
else:
    print(f"ERROR: Segmentation file not found: {seg_path}")

# Set up the view
if loaded_volumes:
    # Set FLAIR as background (best for visualizing edema)
    flair_node = None
    for node in loaded_volumes:
        if "FLAIR" in node.GetName().upper():
            flair_node = node
            break
    
    if flair_node is None:
        flair_node = loaded_volumes[0]
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Center on the tumor (use segmentation bounds if available)
    try:
        bounds = [0]*6
        flair_node.GetBounds(bounds)
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        for color in ["Red", "Green", "Yellow"]:
            sliceWidget = slicer.app.layoutManager().sliceWidget(color)
            sliceLogic = sliceWidget.sliceLogic()
            sliceNode = sliceLogic.GetSliceNode()
            if color == "Red":
                sliceNode.SetSliceOffset(center[2])
            elif color == "Green":
                sliceNode.SetSliceOffset(center[1])
            else:
                sliceNode.SetSliceOffset(center[0])
    except Exception as e:
        print(f"Could not center views: {e}")

# Switch to conventional layout
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)

print("\n=== Setup Complete ===")
print("Task: Use Segment Statistics to calculate volumes and compute the Peritumoral Edema Index")
print("Segmentation loaded with tumor components (labels 1, 2, 4)")
print("Save report to: ~/Documents/SlicerData/BraTS/edema_analysis_report.json")
LOADEOF

# Export environment variables for the script
export SAMPLE_ID
export CASE_DIR="$CASE_DIR"
export BRATS_DIR

# Launch Slicer with the script
echo "Launching 3D Slicer with BraTS data and segmentation..."
sudo -u ga DISPLAY=:1 SAMPLE_ID="$SAMPLE_ID" CASE_DIR="$CASE_DIR" BRATS_DIR="$BRATS_DIR" \
    /opt/Slicer/Slicer --python-script "$LOAD_SCRIPT" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for data to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/edema_task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Tumor Edema Index Assessment"
echo "========================================="
echo ""
echo "A pre-existing tumor segmentation has been loaded with the patient's brain MRI."
echo ""
echo "The segmentation contains BraTS labels:"
echo "  - Label 1: Necrotic/non-enhancing tumor core"
echo "  - Label 2: Peritumoral edema"
echo "  - Label 4: GD-enhancing tumor"
echo ""
echo "Your task:"
echo "  1. Use Segment Statistics module to calculate component volumes"
echo "  2. Calculate PEI = Edema Volume / Core Volume"
echo "     (Core = Label 1 + Label 4)"
echo "  3. Classify prognosis:"
echo "     - Low PEI (< 2.0): More favorable"
echo "     - Moderate PEI (2.0-4.0): Intermediate"  
echo "     - High PEI (> 4.0): Less favorable"
echo ""
echo "Save report to: ~/Documents/SlicerData/BraTS/edema_analysis_report.json"
echo "Required fields: edema_volume_ml, core_volume_ml, pei_ratio, prognostic_class, patient_id"
echo ""