#!/bin/bash
echo "=== Setting up Brain Tumor Documentation Protocol Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
DOC_DIR="$BRATS_DIR/Documentation"
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

# Verify required MRI volumes exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Clean up any previous outputs
echo "Cleaning previous outputs..."
rm -rf "$DOC_DIR" 2>/dev/null || true
mkdir -p "$DOC_DIR"
chown -R ga:ga "$DOC_DIR" 2>/dev/null || true
chmod -R 755 "$DOC_DIR" 2>/dev/null || true

# Remove any stale result files
rm -f /tmp/doc_task_result.json 2>/dev/null || true

# Compute ground truth measurements for verification
echo "Computing ground truth measurements..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"

gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
seg = nib.load(gt_seg_path)
seg_data = seg.get_fdata().astype(np.int32)
voxel_dims = seg.header.get_zooms()[:3]

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# Whole tumor = all non-zero labels
tumor_mask = (seg_data > 0)

# Find the axial slice with maximum tumor area
axial_areas = []
for z in range(tumor_mask.shape[2]):
    area = np.sum(tumor_mask[:, :, z])
    axial_areas.append(area)

max_z = int(np.argmax(axial_areas))
max_slice = tumor_mask[:, :, max_z]

# Get bounding box in the maximum slice
rows = np.any(max_slice, axis=1)
cols = np.any(max_slice, axis=0)

if np.any(rows) and np.any(cols):
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    
    # Calculate dimensions in mm
    dim_r = (rmax - rmin + 1) * float(voxel_dims[0])
    dim_c = (cmax - cmin + 1) * float(voxel_dims[1])
    
    # Max diameter is the larger dimension
    max_diameter = max(dim_r, dim_c)
    perp_diameter = min(dim_r, dim_c)
    
    # Centroid for location
    tumor_coords = np.argwhere(tumor_mask)
    centroid = tumor_coords.mean(axis=0)
    
    # Determine anatomical location based on centroid
    center_x = tumor_mask.shape[0] / 2
    center_y = tumor_mask.shape[1] / 2
    center_z = tumor_mask.shape[2] / 2
    
    # Left/Right (assumes RAS orientation, adjust if needed)
    side = "left" if centroid[0] > center_x else "right"
    
    # Anterior/Posterior/Central
    ap = "anterior" if centroid[1] < center_y * 0.8 else ("posterior" if centroid[1] > center_y * 1.2 else "central")
    
    # Lobe estimation based on z position
    z_fraction = centroid[2] / tumor_mask.shape[2]
    if z_fraction > 0.6:
        lobe = "parietal"
    elif z_fraction > 0.4:
        lobe = "frontal"
    elif z_fraction > 0.2:
        lobe = "temporal"
    else:
        lobe = "occipital"
    
    location = f"{side} {lobe} lobe"
    
    gt_data = {
        "sample_id": sample_id,
        "max_slice_z": max_z,
        "max_axial_diameter_mm": round(float(max_diameter), 2),
        "perpendicular_diameter_mm": round(float(perp_diameter), 2),
        "bidimensional_product_mm2": round(float(max_diameter * perp_diameter), 2),
        "tumor_location": location,
        "centroid_voxels": [float(c) for c in centroid],
        "voxel_dims_mm": [float(v) for v in voxel_dims],
        "bounding_box_max_slice": {
            "rmin": int(rmin), "rmax": int(rmax),
            "cmin": int(cmin), "cmax": int(cmax)
        }
    }
else:
    gt_data = {
        "sample_id": sample_id,
        "error": "Could not compute tumor bounding box"
    }

# Save ground truth for verifier
gt_output_path = "/tmp/documentation_ground_truth.json"
with open(gt_output_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_output_path}")
print(f"Max diameter: {gt_data.get('max_axial_diameter_mm', 'N/A')} mm")
print(f"Perpendicular: {gt_data.get('perpendicular_diameter_mm', 'N/A')} mm")
print(f"Location: {gt_data.get('tumor_location', 'N/A')}")
PYEOF

# Create Slicer Python script to load volumes
cat > /tmp/load_doc_volumes.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Load FLAIR and T1ce (most useful for tumor documentation)
volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
]

print("Loading BraTS MRI volumes for documentation...")
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

print(f"Loaded {len(loaded_nodes)} volumes")

# Set up views with T1_Contrast as background (shows enhancing tumor well)
if loaded_nodes:
    t1ce_node = slicer.util.getNode("T1_Contrast") if slicer.util.getNode("T1_Contrast") else loaded_nodes[0]
    
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(t1ce_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on the data
    bounds = [0]*6
    t1ce_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

# Set conventional layout (four-up view for documentation)
slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

print("Setup complete - ready for tumor documentation task")
print(f"Patient ID: {sample_id}")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the loading script
echo "Launching 3D Slicer with brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_doc_volumes.py > /tmp/slicer_launch.log 2>&1 &

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
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/doc_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Tumor Documentation Protocol"
echo "========================================="
echo ""
echo "Create a complete documentation package for the brain tumor finding."
echo ""
echo "REQUIRED OUTPUTS in ~/Documents/SlicerData/BraTS/Documentation/:"
echo ""
echo "1. Screenshots (PNG format):"
echo "   - axial_view.png (must show measurements)"
echo "   - sagittal_view.png"
echo "   - coronal_view.png"
echo ""
echo "2. Measurement markup:"
echo "   - measurements.mrk.json (contains ruler measurements)"
echo ""
echo "3. Documentation report (JSON):"
echo "   - documentation_report.json with fields:"
echo "     * patient_id, finding, max_axial_diameter_mm"
echo "     * perpendicular_diameter_mm, bidimensional_product_mm2"
echo "     * tumor_location, screenshot_count, documentation_complete"
echo ""
echo "Patient ID: $SAMPLE_ID"
echo ""