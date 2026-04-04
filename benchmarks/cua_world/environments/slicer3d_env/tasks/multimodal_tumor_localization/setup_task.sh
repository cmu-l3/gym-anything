#!/bin/bash
echo "=== Setting up Multi-Modal Tumor Localization Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"
echo "$SAMPLE_ID" > /tmp/task_sample_id.txt

# Verify all required MRI modalities exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
    "${SAMPLE_ID}_t2.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Verify ground truth exists (hidden from agent)
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clean up any previous task outputs
echo "Cleaning up previous task outputs..."
rm -f "$BRATS_DIR/tumor_center.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/localization_report.json" 2>/dev/null || true
rm -f /tmp/localization_task_result.json 2>/dev/null || true

# Calculate and save ground truth centroid for verification
echo "Computing ground truth tumor centroid..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
gt_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

if os.path.exists(gt_path):
    print(f"Loading ground truth: {gt_path}")
    seg_nii = nib.load(gt_path)
    seg_data = seg_nii.get_fdata().astype(np.int32)
    affine = seg_nii.affine
    voxel_dims = seg_nii.header.get_zooms()[:3]
    
    # Get all tumor voxels (BraTS labels: 1=necrotic, 2=edema, 4=enhancing)
    tumor_mask = (seg_data > 0)
    tumor_coords_voxel = np.argwhere(tumor_mask)
    
    if len(tumor_coords_voxel) > 0:
        # Calculate centroid in voxel space
        centroid_voxel = tumor_coords_voxel.mean(axis=0)
        
        # Convert to RAS coordinates using affine
        centroid_homogeneous = np.append(centroid_voxel, 1)
        centroid_ras = affine.dot(centroid_homogeneous)[:3]
        
        # Get volume bounds
        min_coords = tumor_coords_voxel.min(axis=0)
        max_coords = tumor_coords_voxel.max(axis=0)
        
        # Calculate tumor volume
        voxel_volume_mm3 = float(np.prod(voxel_dims))
        tumor_volume_mm3 = np.sum(tumor_mask) * voxel_volume_mm3
        tumor_volume_ml = tumor_volume_mm3 / 1000.0
        
        # Save ground truth for verifier
        gt_info = {
            'sample_id': sample_id,
            'centroid_voxel': centroid_voxel.tolist(),
            'centroid_ras': centroid_ras.tolist(),
            'tumor_voxel_count': int(np.sum(tumor_mask)),
            'tumor_volume_ml': float(tumor_volume_ml),
            'voxel_dims_mm': [float(v) for v in voxel_dims],
            'volume_bounds_voxel': {
                'min': min_coords.tolist(),
                'max': max_coords.tolist()
            },
            'affine': affine.tolist()
        }
        
        gt_output = os.path.join(gt_dir, f"{sample_id}_centroid_gt.json")
        with open(gt_output, 'w') as f:
            json.dump(gt_info, f, indent=2)
        
        print(f"Ground truth centroid (RAS): R={centroid_ras[0]:.1f}, A={centroid_ras[1]:.1f}, S={centroid_ras[2]:.1f}")
        print(f"Tumor voxel count: {np.sum(tumor_mask)}")
        print(f"Tumor volume: {tumor_volume_ml:.2f} mL")
        print(f"Ground truth saved to: {gt_output}")
    else:
        print("WARNING: No tumor found in ground truth segmentation")
else:
    print(f"WARNING: Ground truth not found at {gt_path}")
PYEOF

# Create a Slicer Python script to load all volumes
cat > /tmp/load_multimodal_volumes.py << 'PYEOF'
import slicer
import os

sample_dir = os.environ.get('SAMPLE_DIR', '/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000')
sample_id = os.environ.get('SAMPLE_ID', 'BraTS2021_00000')

# Define volumes to load with display names
volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("="*60)
print("Loading Multi-Modal BraTS MRI volumes...")
print("="*60)
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"    Loaded: {node.GetName()}")
        else:
            print(f"    ERROR loading {filepath}")
    else:
        print(f"  WARNING: File not found: {filepath}")

print(f"\nSuccessfully loaded {len(loaded_nodes)} volumes")

# Set up the views for multi-modal visualization
if loaded_nodes:
    # Make FLAIR the background volume (good for seeing overall tumor extent)
    flair_node = None
    for node in loaded_nodes:
        if node.GetName() == "FLAIR":
            flair_node = node
            break
    if not flair_node:
        flair_node = loaded_nodes[0]
    
    # Set FLAIR as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Get volume center and navigate there
    bounds = [0]*6
    flair_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":    # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Yellow = Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print("\nViews configured:")
    print(f"  - FLAIR set as background volume")
    print(f"  - Views centered at: ({center[0]:.1f}, {center[1]:.1f}, {center[2]:.1f})")

print("\n" + "="*60)
print("Setup complete - ready for tumor localization task")
print("="*60)
print("\nTASK: Place a fiducial marker at the tumor center")
print("1. Use View menu to set up linked views")
print("2. Navigate to find the tumor")
print("3. Use Markups > Point List to place a fiducial")
print("4. Name it 'TumorCenter'")
print("5. Save markup and create report")
print("="*60)
PYEOF

# Export environment variables for the Python script
export SAMPLE_DIR="$SAMPLE_DIR"
export SAMPLE_ID="$SAMPLE_ID"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with multi-modal BraTS volumes..."
sudo -u ga DISPLAY=:1 SAMPLE_DIR="$SAMPLE_DIR" SAMPLE_ID="$SAMPLE_ID" /opt/Slicer/Slicer --python-script /tmp/load_multimodal_volumes.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volumes to fully load
sleep 5

# Take initial screenshot
mkdir -p /tmp/task_evidence
take_screenshot /tmp/task_evidence/initial_state.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Multi-Modal Brain Tumor Localization"
echo "==========================================="
echo ""
echo "Four MRI sequences are loaded:"
echo "  - FLAIR: Highlights edema (bright around tumor)"
echo "  - T1: Anatomical reference"
echo "  - T1_Contrast: Shows enhancing tumor core (bright ring)"
echo "  - T2: Shows tumor and edema as bright"
echo ""
echo "Your goal:"
echo "  1. Set up linked views to navigate all modalities together"
echo "  2. Find the brain tumor"
echo "  3. Place a fiducial marker at tumor center (name it 'TumorCenter')"
echo "  4. Save markup to: ~/Documents/SlicerData/BraTS/tumor_center.mrk.json"
echo "  5. Create report: ~/Documents/SlicerData/BraTS/localization_report.json"
echo ""
echo "Report JSON should contain:"
echo '  {"R": <value>, "A": <value>, "S": <value>,'
echo '   "most_helpful_modality": "<modality>",'
echo '   "observations": "<your observations>"}'
echo ""