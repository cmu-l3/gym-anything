#!/bin/bash
echo "=== Setting up Import Labelmap Segments Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb/patient_5"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CT_VOLUME="$IRCADB_DIR/ct_volume.nii.gz"
COMBINED_LABELMAP="$IRCADB_DIR/combined_labels.nii.gz"

# Create directories
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Ensure Python dependencies
pip install -q numpy nibabel scipy 2>/dev/null || pip3 install -q numpy nibabel scipy 2>/dev/null || true

# ============================================================
# Prepare IRCADb data
# ============================================================
echo "Preparing IRCADb patient 5 data..."

# Run the IRCADb preparation script
export PATIENT_NUM=5
/workspace/scripts/prepare_ircadb_data.sh 5 || {
    echo "IRCADb preparation returned non-zero, checking if data exists anyway..."
}

# Save patient number for later
echo "5" > /tmp/ircadb_patient_num

# ============================================================
# Create combined labelmap and CT volume for the task
# ============================================================
echo "Creating task data files..."

python3 << 'PYEOF'
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

ircadb_dir = "/home/ga/Documents/SlicerData/IRCADb/patient_5"
gt_dir = "/var/lib/slicer/ground_truth"

# Check if ground truth segmentation exists from prepare_ircadb_data.sh
gt_seg_path = os.path.join(gt_dir, "ircadb_patient5_seg.nii.gz")

if not os.path.exists(gt_seg_path):
    print("Ground truth not found, creating synthetic data...")
    
    # Create synthetic data for testing
    np.random.seed(42)
    
    # Volume dimensions
    nx, ny, nz = 256, 256, 100
    spacing = (0.78125, 0.78125, 2.5)
    
    # Create affine matrix
    affine = np.eye(4)
    affine[0, 0] = spacing[0]
    affine[1, 1] = spacing[1]
    affine[2, 2] = spacing[2]
    
    # Create CT volume with realistic HU values
    ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)
    
    # Create body outline (elliptical)
    Y, X = np.ogrid[:nx, :ny]
    center_x, center_y = nx // 2, ny // 2
    body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (80**2)) <= 1.0
    
    # Set air outside body
    for z in range(nz):
        ct_data[:, :, z][~body_mask] = -1000
    
    # Create label map
    label_data = np.zeros((nx, ny, nz), dtype=np.int16)
    
    # Label 1: Liver (right side, large region)
    liver_cx, liver_cy = center_x - 30, center_y - 10
    for z in range(20, 80):
        liver_mask = ((X - liver_cx)**2 / (45**2) + (Y - liver_cy)**2 / (40**2)) <= 1.0
        label_data[:, :, z][liver_mask & body_mask] = 1
        # Make liver brighter in CT
        ct_data[:, :, z][liver_mask & body_mask] = np.random.normal(60, 10, (np.sum(liver_mask & body_mask),)).astype(np.int16)
    
    # Label 2: Tumor (inside liver)
    tumor_cx, tumor_cy = center_x - 20, center_y - 5
    for z in range(35, 55):
        tumor_mask = ((X - tumor_cx)**2 + (Y - tumor_cy)**2) <= 12**2
        label_data[:, :, z][tumor_mask & body_mask] = 2
        ct_data[:, :, z][tumor_mask & body_mask] = np.random.normal(45, 8, (np.sum(tumor_mask & body_mask),)).astype(np.int16)
    
    # Label 3: Portal vein (tubular structure)
    pv_cx, pv_cy = center_x - 40, center_y + 20
    for z in range(25, 70):
        pv_mask = ((X - pv_cx)**2 + (Y - pv_cy)**2) <= 6**2
        label_data[:, :, z][pv_mask & body_mask] = 3
        ct_data[:, :, z][pv_mask & body_mask] = np.random.normal(150, 20, (np.sum(pv_mask & body_mask),)).astype(np.int16)
    
    # Save ground truth segmentation
    gt_nii = nib.Nifti1Image(label_data, affine)
    os.makedirs(gt_dir, exist_ok=True)
    nib.save(gt_nii, gt_seg_path)
    print(f"Created ground truth: {gt_seg_path}")
    
    # Save CT volume
    ct_path = os.path.join(ircadb_dir, "ct_volume.nii.gz")
    ct_nii = nib.Nifti1Image(ct_data, affine)
    os.makedirs(ircadb_dir, exist_ok=True)
    nib.save(ct_nii, ct_path)
    print(f"Created CT volume: {ct_path}")

# Now create the combined labelmap for the agent
gt_seg_path = os.path.join(gt_dir, "ircadb_patient5_seg.nii.gz")
combined_path = os.path.join(ircadb_dir, "combined_labels.nii.gz")
ct_path = os.path.join(ircadb_dir, "ct_volume.nii.gz")

if os.path.exists(gt_seg_path):
    # Copy ground truth to agent-accessible location
    seg_nii = nib.load(gt_seg_path)
    seg_data = seg_nii.get_fdata().astype(np.int16)
    
    # Save as combined labelmap for agent
    combined_nii = nib.Nifti1Image(seg_data, seg_nii.affine, seg_nii.header)
    nib.save(combined_nii, combined_path)
    print(f"Created combined labelmap: {combined_path}")
    
    # Compute label statistics for ground truth
    unique_labels = np.unique(seg_data)
    label_counts = {int(l): int(np.sum(seg_data == l)) for l in unique_labels if l > 0}
    
    gt_info = {
        "shape": list(seg_data.shape),
        "unique_labels": [int(l) for l in unique_labels],
        "label_voxel_counts": label_counts,
        "total_nonzero_voxels": int(np.sum(seg_data > 0)),
        "expected_segment_count": len([l for l in unique_labels if l > 0])
    }
    
    gt_info_path = os.path.join(gt_dir, "ircadb_patient5_label_info.json")
    with open(gt_info_path, "w") as f:
        json.dump(gt_info, f, indent=2)
    print(f"Ground truth info saved: {gt_info_path}")
    print(f"Labels: {label_counts}")
    
    # Check if CT volume exists, if not create from DICOM or synthetic
    if not os.path.exists(ct_path):
        print("CT volume not found, creating placeholder...")
        # Create a CT-like volume matching the labelmap dimensions
        ct_data = np.random.normal(40, 20, seg_data.shape).astype(np.int16)
        ct_data[seg_data == 0] = -1000  # Air outside
        ct_data[seg_data == 1] = np.random.normal(60, 10, (np.sum(seg_data == 1),)).astype(np.int16)  # Liver
        ct_data[seg_data == 2] = np.random.normal(45, 8, (np.sum(seg_data == 2),)).astype(np.int16)  # Tumor
        ct_data[seg_data == 3] = np.random.normal(150, 20, (np.sum(seg_data == 3),)).astype(np.int16)  # Portal vein
        
        ct_nii = nib.Nifti1Image(ct_data, seg_nii.affine, seg_nii.header)
        nib.save(ct_nii, ct_path)
        print(f"Created CT volume: {ct_path}")
else:
    print(f"ERROR: Ground truth not found at {gt_seg_path}")
    sys.exit(1)

print("Data preparation complete!")
PYEOF

# Set permissions
chown -R ga:ga "$IRCADB_DIR" 2>/dev/null || true
chmod -R 755 "$IRCADB_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Verify files exist
echo ""
echo "Verifying data files..."
if [ -f "$CT_VOLUME" ]; then
    echo "  CT volume: $(du -h "$CT_VOLUME" | cut -f1)"
else
    echo "  ERROR: CT volume not found!"
fi

if [ -f "$COMBINED_LABELMAP" ]; then
    echo "  Labelmap: $(du -h "$COMBINED_LABELMAP" | cut -f1)"
else
    echo "  ERROR: Labelmap not found!"
fi

# Record initial state - count segmentation nodes
echo "0" > /tmp/initial_segmentation_count.txt

# Clear any previous results
rm -f /tmp/labelmap_task_result.json 2>/dev/null || true

# ============================================================
# Launch 3D Slicer
# ============================================================
echo ""
echo "Launching 3D Slicer..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer without any files loaded (agent should load them)
if [ -x "/opt/Slicer/Slicer" ]; then
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash > /tmp/slicer_launch.log 2>&1 &"
else
    echo "ERROR: Slicer not found at /opt/Slicer/Slicer"
    exit 1
fi

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Maximize and focus
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "Task: Import multi-label segmentation and separate into distinct segments"
echo ""
echo "Data files:"
echo "  CT volume:  $CT_VOLUME"
echo "  Labelmap:   $COMBINED_LABELMAP"
echo ""
echo "Label mapping:"
echo "  0 = Background"
echo "  1 = Liver"
echo "  2 = Tumor"
echo "  3 = Portal Vein"
echo ""
echo "Instructions:"
echo "  1. Load CT volume using File > Add Data"
echo "  2. Load labelmap using File > Add Data (as labelmap volume)"
echo "  3. In Segment Editor or Segmentations module, import the labelmap"
echo "  4. Verify 3 distinct colored segments are created"