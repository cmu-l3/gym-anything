#!/bin/bash
echo "=== Setting up Brain Midline Shift Measurement Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS brain MRI data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"

echo "Using sample: $SAMPLE_ID"

# Verify all required files exist
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

# Verify ground truth segmentation exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth segmentation verified"

# ============================================================
# Compute ground truth midline shift from tumor segmentation
# ============================================================
echo "Computing ground truth midline shift..."

mkdir -p "$GROUND_TRUTH_DIR"

python3 << PYEOF
import os
import json
import numpy as np
import sys

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
brats_dir = "$BRATS_DIR"

seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
flair_path = os.path.join(brats_dir, sample_id, f"{sample_id}_flair.nii.gz")
output_path = os.path.join(gt_dir, f"{sample_id}_midline_gt.json")

print(f"Loading segmentation: {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
voxel_dims = seg_nii.header.get_zooms()[:3]

print(f"Volume shape: {seg_data.shape}")
print(f"Voxel dimensions: {voxel_dims} mm")

# Load FLAIR for brain boundary estimation
flair_data = None
if os.path.exists(flair_path):
    flair_nii = nib.load(flair_path)
    flair_data = flair_nii.get_fdata()

nx, ny, nz = seg_data.shape

# Ideal midline is at center of x-axis (assuming RAS or similar orientation)
ideal_midline_x = nx / 2.0

# Find tumor mask (all labels > 0)
tumor_mask = (seg_data > 0)

if not np.any(tumor_mask):
    print("No tumor found - outputting minimal shift")
    result = {
        "sample_id": sample_id,
        "shift_mm": 0.0,
        "shift_voxels": 0.0,
        "direction": "none",
        "severity": "minimal",
        "max_shift_slice": int(nz // 2),
        "max_shift_slice_mm": float(nz // 2 * voxel_dims[2]),
        "tumor_volume_ml": 0.0,
        "method": "no_tumor_detected"
    }
else:
    # Compute tumor center of mass and estimate midline shift
    # The tumor causes mass effect, pushing midline structures away
    
    max_shift_voxels = 0.0
    max_shift_slice = 0
    shift_direction = "none"
    
    # Analyze each axial slice
    for z in range(nz):
        slice_tumor = tumor_mask[:, :, z]
        if not np.any(slice_tumor):
            continue
        
        # Get tumor extent in this slice
        tumor_rows = np.where(np.any(slice_tumor, axis=1))[0]
        if len(tumor_rows) == 0:
            continue
        
        tumor_center_x = (tumor_rows.min() + tumor_rows.max()) / 2.0
        
        # Estimate brain center for this slice
        brain_center_x = ideal_midline_x
        if flair_data is not None:
            brain_slice = flair_data[:, :, z]
            if np.any(brain_slice > 0):
                threshold = np.percentile(brain_slice[brain_slice > 0], 10)
                brain_mask = brain_slice > threshold
                if np.any(brain_mask):
                    brain_rows = np.where(np.any(brain_mask, axis=1))[0]
                    if len(brain_rows) > 0:
                        brain_center_x = (brain_rows.min() + brain_rows.max()) / 2.0
        
        # Estimate midline shift based on tumor position
        # Tumor pushes midline away from its side
        tumor_volume_slice = np.sum(slice_tumor)
        if tumor_volume_slice > 100:  # Meaningful tumor presence
            if tumor_center_x > brain_center_x:
                # Tumor on "right" -> pushes midline left
                relative_shift = (tumor_center_x - brain_center_x) * 0.25
                if abs(relative_shift) > abs(max_shift_voxels):
                    max_shift_voxels = relative_shift
                    max_shift_slice = z
                    shift_direction = "left"
            else:
                # Tumor on "left" -> pushes midline right
                relative_shift = (brain_center_x - tumor_center_x) * 0.25
                if abs(relative_shift) > abs(max_shift_voxels):
                    max_shift_voxels = relative_shift
                    max_shift_slice = z
                    shift_direction = "right"
    
    # Convert to mm
    shift_mm = abs(max_shift_voxels) * voxel_dims[0]
    
    # Adjust based on total tumor volume (larger tumors cause more shift)
    total_tumor_voxels = np.sum(tumor_mask)
    tumor_volume_ml = total_tumor_voxels * np.prod(voxel_dims) / 1000.0
    
    # Heuristic adjustment based on clinical observations
    if tumor_volume_ml > 100:
        shift_mm = max(shift_mm, 10.0)
    elif tumor_volume_ml > 50:
        shift_mm = max(shift_mm, 5.0)
    elif tumor_volume_ml > 20:
        shift_mm = max(shift_mm, 2.0)
    
    # Ensure minimal shift for small tumors
    if tumor_volume_ml < 5:
        shift_mm = min(shift_mm, 1.0)
    
    # Classify severity
    if shift_mm < 3:
        severity = "minimal"
    elif shift_mm < 5:
        severity = "moderate"
    elif shift_mm < 10:
        severity = "severe"
    else:
        severity = "critical"
    
    result = {
        "sample_id": sample_id,
        "shift_mm": round(float(shift_mm), 1),
        "shift_voxels": round(float(abs(max_shift_voxels)), 2),
        "direction": shift_direction,
        "severity": severity,
        "max_shift_slice": int(max_shift_slice),
        "max_shift_slice_mm": round(float(max_shift_slice * voxel_dims[2]), 1),
        "tumor_volume_ml": round(float(tumor_volume_ml), 1),
        "voxel_dims_mm": [round(float(v), 3) for v in voxel_dims],
        "image_dimensions": list(seg_data.shape),
        "method": "tumor_mass_effect_estimate"
    }

# Save result
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"\nGround truth midline shift computed:")
print(json.dumps(result, indent=2))
print(f"\nSaved to: {output_path}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_midline_gt.json" ]; then
    echo "ERROR: Failed to compute ground truth midline shift"
    exit 1
fi
echo "Ground truth midline shift computed (hidden from agent)"

# Clean up any previous task outputs
rm -f /tmp/midline_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/midline_measurement.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/midline_shift_report.json" 2>/dev/null || true

# Create a Slicer Python script to load all volumes
cat > /tmp/load_brats_midline.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Define volumes to load with display names
volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("Loading BraTS MRI volumes for midline shift assessment...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)

print(f"Loaded {len(loaded_nodes)} volumes")

if loaded_nodes:
    # Make FLAIR the background (best for midline visualization)
    flair_node = None
    for node in loaded_nodes:
        if "FLAIR" in node.GetName():
            flair_node = node
            break
    if flair_node is None:
        flair_node = loaded_nodes[0]
    
    # Set slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())
    
    # Set up axial view as primary (Red slice is typically axial)
    layoutManager = slicer.app.layoutManager()
    layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Get volume center and set slice offsets
    bounds = [0]*6
    flair_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Set Red (axial) to center of brain
    redWidget = layoutManager.sliceWidget("Red")
    redWidget.sliceLogic().GetSliceNode().SetSliceOffset(center[2])
    
    # Set Green (coronal) to center
    greenWidget = layoutManager.sliceWidget("Green")
    greenWidget.sliceLogic().GetSliceNode().SetSliceOffset(center[1])
    
    # Set Yellow (sagittal) to midline
    yellowWidget = layoutManager.sliceWidget("Yellow")
    yellowWidget.sliceLogic().GetSliceNode().SetSliceOffset(center[0])

print("Setup complete - ready for midline shift measurement task")
print("Use the axial (Red) view to measure midline shift")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_midline.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Maximize window
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

# Wait for volumes to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/midline_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Midline Shift Measurement"
echo "======================================"
echo ""
echo "The patient has a brain tumor and new symptoms. Measure the midline shift."
echo ""
echo "Your goal:"
echo "  1. Navigate to axial view (FLAIR sequence recommended)"
echo "  2. Identify ideal midline (center of brain/skull)"
echo "  3. Find the septum pellucidum or other midline structures"
echo "  4. Scroll to find maximum deviation"
echo "  5. Use Markups ruler to measure shift (mm)"
echo "  6. Document direction (left/right) and severity"
echo ""
echo "Severity classification:"
echo "  - Minimal: < 3mm"
echo "  - Moderate: 3-5mm"
echo "  - Severe: 5-10mm"
echo "  - Critical: > 10mm"
echo ""
echo "Save your outputs:"
echo "  - Measurement: ~/Documents/SlicerData/BraTS/midline_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/midline_shift_report.json"
echo ""