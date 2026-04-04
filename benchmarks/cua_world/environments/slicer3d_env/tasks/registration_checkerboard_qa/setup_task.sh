#!/bin/bash
echo "=== Setting up Registration Checkerboard QA Task ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
MRHEAD_FILE="$SAMPLE_DIR/MRHead.nrrd"
MRHEAD_SHIFTED_FILE="$SAMPLE_DIR/MRHead_Shifted.nrrd"

# Create directories
mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clear any previous outputs
rm -f "$EXPORTS_DIR/registration_qa_checkerboard.png" 2>/dev/null || true
rm -f "$EXPORTS_DIR/registration_qa_report.json" 2>/dev/null || true
rm -f /tmp/checkerboard_task_result.json 2>/dev/null || true

# ============================================================
# Ensure MRHead sample data exists
# ============================================================
if [ ! -f "$MRHEAD_FILE" ] || [ $(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
    echo "Downloading MRHead sample data..."
    curl -L -o "$MRHEAD_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget -O "$MRHEAD_FILE" --timeout=120 \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
    echo "WARNING: Could not download MRHead sample data"
fi

if [ ! -f "$MRHEAD_FILE" ] || [ $(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo 0) -lt 100000 ]; then
    echo "ERROR: MRHead sample data not available"
    exit 1
fi

echo "MRHead file: $(du -h "$MRHEAD_FILE" | cut -f1)"

# ============================================================
# Create shifted version (4mm anterior shift)
# ============================================================
echo "Creating shifted version of MRHead (4mm anterior shift)..."

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

from scipy.ndimage import shift as ndshift

sample_dir = "/home/ga/Documents/SlicerData/SampleData"
gt_dir = "/var/lib/slicer/ground_truth"
mrhead_path = os.path.join(sample_dir, "MRHead.nrrd")
shifted_path = os.path.join(sample_dir, "MRHead_Shifted.nrrd")

# Load MRHead
print(f"Loading {mrhead_path}...")
img = nib.load(mrhead_path)
data = img.get_fdata()
affine = img.affine
header = img.header

print(f"MRHead shape: {data.shape}")
print(f"MRHead affine:\n{affine}")

# Get voxel dimensions
voxel_dims = header.get_zooms()[:3]
print(f"Voxel dimensions: {voxel_dims} mm")

# Apply 4mm shift in anterior direction (positive Y in RAS coordinates)
# Convert mm to voxels
shift_mm = 4.0
shift_direction = [0, 1, 0]  # Y direction (anterior in RAS)

# Calculate voxel shift
# Need to determine which axis is Y based on affine
# For simplicity, assume standard orientation where axis 1 is A-P
voxel_shift = [0, 0, 0]
for i in range(3):
    if abs(affine[1, i]) > 0.5:  # Find the axis corresponding to Y (anterior-posterior)
        voxel_shift[i] = shift_mm / abs(voxel_dims[i])
        break
else:
    # Fallback: shift along axis 1
    voxel_shift[1] = shift_mm / abs(voxel_dims[1]) if voxel_dims[1] > 0 else shift_mm

print(f"Applying voxel shift: {voxel_shift}")

# Apply shift using scipy
shifted_data = ndshift(data, voxel_shift, order=1, mode='constant', cval=0)

# Save shifted volume with same affine (simulates misregistration)
shifted_img = nib.Nifti1Image(shifted_data.astype(data.dtype), affine, header)
nib.save(shifted_img, shifted_path)
print(f"Saved shifted volume to {shifted_path}")

# Save ground truth
gt_data = {
    "shift_vector_mm": [0, shift_mm, 0],
    "shift_magnitude_mm": shift_mm,
    "shift_direction": "anterior",
    "transform_type": "translation",
    "voxel_shift_applied": voxel_shift,
    "expected_detection": True,
    "expected_alignment_quality": "poor",
    "expected_misalignment_detected": True
}

gt_path = os.path.join(gt_dir, "registration_shift_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Saved ground truth to {gt_path}")

print("Shifted volume creation complete")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create shifted volume"
    exit 1
fi

# Verify shifted file was created
if [ ! -f "$MRHEAD_SHIFTED_FILE" ]; then
    echo "ERROR: Shifted file was not created"
    exit 1
fi

echo "Shifted file: $(du -h "$MRHEAD_SHIFTED_FILE" | cut -f1)"

# Set permissions
chown -R ga:ga "$SAMPLE_DIR"
chown -R ga:ga "$EXPORTS_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# ============================================================
# Launch 3D Slicer with both volumes
# ============================================================
echo "Launching 3D Slicer with both volumes..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load both volumes
cat > /tmp/load_registration_volumes.py << 'LOADPY'
import slicer
import os

sample_dir = "/home/ga/Documents/SlicerData/SampleData"
mrhead_path = os.path.join(sample_dir, "MRHead.nrrd")
shifted_path = os.path.join(sample_dir, "MRHead_Shifted.nrrd")

# Load MRHead (baseline)
print(f"Loading {mrhead_path}...")
baseline_node = slicer.util.loadVolume(mrhead_path)
if baseline_node:
    baseline_node.SetName("MRHead")
    print(f"Loaded baseline volume: {baseline_node.GetName()}")
else:
    print("ERROR: Failed to load baseline volume")

# Load MRHead_Shifted (follow-up)
print(f"Loading {shifted_path}...")
shifted_node = slicer.util.loadVolume(shifted_path)
if shifted_node:
    shifted_node.SetName("MRHead_Shifted")
    print(f"Loaded shifted volume: {shifted_node.GetName()}")
else:
    print("ERROR: Failed to load shifted volume")

# Set up default view
slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Make baseline volume visible in background
if baseline_node:
    slicer.util.setSliceViewerLayers(background=baseline_node)
    
# Reset field of view
slicer.util.resetSliceViews()

print("Volumes loaded. Ready for checkerboard comparison.")
LOADPY

# Launch Slicer
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_registration_volumes.py > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start and load volumes..."
sleep 10

# Wait for Slicer window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for volumes to load
sleep 10

# Maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/checkerboard_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "Two volumes are loaded in 3D Slicer:"
echo "  1. MRHead (baseline scan)"
echo "  2. MRHead_Shifted (shifted by 4mm - simulates imperfect registration)"
echo ""
echo "YOUR TASK:"
echo "  1. Create a checkerboard visualization comparing the two volumes"
echo "  2. Navigate to the lateral ventricles (axial view, mid-brain level)"
echo "  3. Assess alignment quality at tile boundaries"
echo "  4. Save screenshot to: ~/Documents/SlicerData/Exports/registration_qa_checkerboard.png"
echo "  5. Save report to: ~/Documents/SlicerData/Exports/registration_qa_report.json"
echo ""
echo "Hint: Use the slice view controller (pin icon) or Compare Volumes module"
echo "      to access checkerboard compositing mode."