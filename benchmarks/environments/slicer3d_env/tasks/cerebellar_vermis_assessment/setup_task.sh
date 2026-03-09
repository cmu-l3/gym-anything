#!/bin/bash
echo "=== Setting up Cerebellar Vermis Assessment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date -Iseconds)"

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS brain MRI data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
FLAIR_FILE="$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"

echo "Using sample: $SAMPLE_ID"

# Verify FLAIR exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR MRI not found at $FLAIR_FILE"
    exit 1
fi
echo "FLAIR MRI found: $FLAIR_FILE"

# Create ground truth measurements for vermis
echo "Computing reference vermis measurements..."
mkdir -p "$GROUND_TRUTH_DIR"

python3 << 'PYEOF'
import os
import json
import numpy as np
import sys

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
gt_dir = "/var/lib/slicer/ground_truth"

flair_path = os.path.join(brats_dir, sample_id, f"{sample_id}_flair.nii.gz")
os.makedirs(gt_dir, exist_ok=True)

print(f"Loading FLAIR: {flair_path}")
nii = nib.load(flair_path)
data = nii.get_fdata()
affine = nii.affine
spacing = nii.header.get_zooms()[:3]

print(f"Volume shape: {data.shape}, spacing: {spacing}")

# Find the posterior fossa region (inferior 1/3 of volume)
nz = data.shape[2]
nx, ny = data.shape[0], data.shape[1]

# Cerebellar region is typically in inferior slices
inferior_start = int(nz * 0.1)
inferior_end = int(nz * 0.4)

# Find midline (center x)
mid_x = nx // 2

# Analyze intensity in cerebellar region to find vermis
vermis_candidates = []

for z in range(inferior_start, inferior_end):
    # Get sagittal slice at midline
    sagittal = data[mid_x-5:mid_x+5, :, z].mean(axis=0)
    
    # Vermis is in posterior-inferior region
    posterior_half = sagittal[ny//2:]
    
    # Find peak intensity region
    threshold = np.percentile(posterior_half[posterior_half > 0], 60) if np.any(posterior_half > 0) else 0
    bright_region = np.where(posterior_half > threshold)[0]
    
    if len(bright_region) > 10:
        ap_start = bright_region[0] + ny//2
        ap_end = bright_region[-1] + ny//2
        ap_extent = (ap_end - ap_start) * spacing[1]
        
        if 15 < ap_extent < 60:
            vermis_candidates.append({
                'z': z,
                'ap_start': ap_start,
                'ap_end': ap_end,
                'ap_diameter_mm': float(ap_extent),
                'y_center': (ap_start + ap_end) / 2
            })

# Find best candidate
if vermis_candidates:
    vermis_candidates.sort(key=lambda x: x['ap_diameter_mm'], reverse=True)
    reasonable = [c for c in vermis_candidates if 20 < c['ap_diameter_mm'] < 45]
    
    if reasonable:
        best = reasonable[0]
    else:
        best = vermis_candidates[len(vermis_candidates)//2]
else:
    best_z = (inferior_start + inferior_end) // 2
    best = {
        'z': best_z,
        'ap_start': int(ny * 0.55),
        'ap_end': int(ny * 0.75),
        'ap_diameter_mm': float((ny * 0.2) * spacing[1]),
        'y_center': ny * 0.65
    }

# Convert to physical coordinates
z_mm = best['z'] * spacing[2]
y_start_mm = best['ap_start'] * spacing[1]
y_end_mm = best['ap_end'] * spacing[1]

# Estimate height
height_mm = best['ap_diameter_mm'] * 0.9

# Determine clinical classification
ap_diam = best['ap_diameter_mm']
if ap_diam >= 25:
    classification = "Normal"
    morphology = "Normal vermis morphology"
elif ap_diam >= 18:
    classification = "Borderline"
    morphology = "Mildly reduced vermis size"
else:
    classification = "Hypoplastic"
    morphology = "Vermis hypoplasia"

# Define expected measurement region
expected_region = {
    'x_min': float((mid_x - 20) * spacing[0]),
    'x_max': float((mid_x + 20) * spacing[0]),
    'y_min': float(y_start_mm - 15),
    'y_max': float(y_end_mm + 15),
    'z_min': float((inferior_start - 10) * spacing[2]),
    'z_max': float((inferior_end + 10) * spacing[2]),
}

ground_truth = {
    'sample_id': sample_id,
    'reference_ap_diameter_mm': float(round(ap_diam, 1)),
    'reference_height_mm': float(round(height_mm, 1)),
    'reference_z_slice': int(best['z']),
    'reference_z_mm': float(round(z_mm, 1)),
    'expected_classification': classification,
    'expected_morphology': morphology,
    'measurement_tolerance_mm': 5.0,
    'expected_region': expected_region,
    'volume_shape': list(data.shape),
    'voxel_spacing_mm': [float(s) for s in spacing],
    'midline_x_voxel': int(mid_x),
}

gt_path = os.path.join(gt_dir, f"{sample_id}_vermis_gt.json")
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"Reference AP diameter: {ap_diam:.1f} mm")
print(f"Expected classification: {classification}")
PYEOF

# Export environment variables
export SAMPLE_ID
export BRATS_DIR

# Clean up any previous results
rm -f /tmp/vermis_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/vermis_measurement.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/vermis_report.json" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "sample_id": "$SAMPLE_ID",
    "flair_file": "$FLAIR_FILE",
    "measurement_exists": false,
    "report_exists": false
}
EOF

# Kill any existing Slicer
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer Python script to load FLAIR
cat > /tmp/load_flair_volume.py << PYEOF
import slicer
import os

flair_path = "$FLAIR_FILE"
sample_id = "$SAMPLE_ID"

print(f"Loading FLAIR MRI: {sample_id}...")

volume_node = slicer.util.loadVolume(flair_path)

if volume_node:
    volume_node.SetName("FLAIR_Brain_MRI")
    
    # Set appropriate brain window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetAutoWindowLevel(True)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on data (start with axial view)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
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
    
    print(f"FLAIR loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load FLAIR volume")

print("Setup complete - ready for vermis measurement task")
PYEOF

# Launch Slicer with the Python script
echo "Launching 3D Slicer with FLAIR MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_flair_volume.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to load..."
sleep 10

for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for data loading
sleep 15

# Maximize and focus Slicer
SLICER_WID=$(DISPLAY=:1 wmctrl -l | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    echo "Found Slicer window: $SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Create output directory
mkdir -p "$BRATS_DIR"
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Cerebellar Vermis Width Measurement"
echo "=========================================="
echo ""
echo "You are given a brain MRI scan (FLAIR sequence)."
echo ""
echo "Your goal:"
echo "  1. Switch to SAGITTAL view (mid-sagittal plane)"
echo "  2. Navigate INFERIORLY to the posterior fossa"
echo "  3. Identify the cerebellar vermis (midline structure)"
echo "  4. Measure AP diameter using Markups ruler tool"
echo "  5. Save measurement: ~/Documents/SlicerData/BraTS/vermis_measurement.mrk.json"
echo "  6. Create report: ~/Documents/SlicerData/BraTS/vermis_report.json"
echo ""
echo "Report should contain:"
echo "  - ap_diameter: measurement in mm"
echo "  - morphology: description"
echo "  - classification: Normal (>=25mm), Borderline (18-25mm), or Hypoplastic (<18mm)"
echo ""