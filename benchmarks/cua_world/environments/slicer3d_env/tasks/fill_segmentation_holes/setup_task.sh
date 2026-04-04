#!/bin/bash
echo "=== Setting up Fill Segmentation Internal Holes Task ==="

source /workspace/scripts/task_utils.sh

DATA_DIR="/home/ga/Documents/SlicerData/LungHoles"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$DATA_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean previous results
rm -f "$EXPORTS_DIR/filled_lung_segment.seg.nrrd" 2>/dev/null || true
rm -f /tmp/fill_holes_result.json 2>/dev/null || true
rm -f /tmp/initial_segment_stats.json 2>/dev/null || true

# ============================================================
# Generate synthetic chest CT with lung segmentation that has holes
# Using synthetic data for reliable testing (real LIDC download is slow)
# ============================================================

echo "Generating chest CT with holey lung segmentation..."

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

from scipy.ndimage import binary_erosion, label as scipy_label

data_dir = "/home/ga/Documents/SlicerData/LungHoles"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# Create realistic chest CT volume
# Dimensions: 256 x 256 x 100 (axial slices)
nx, ny, nz = 256, 256, 100
spacing = (0.78, 0.78, 2.5)  # mm per voxel

# Affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# ============================================================
# Create CT volume with realistic HU values
# ============================================================
print("Creating CT volume...")

ct_data = np.zeros((nx, ny, nz), dtype=np.int16)

# Fill with soft tissue background
ct_data[:] = np.random.normal(40, 10, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical thorax shape)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2
body_mask = ((X - center_x)**2 / (110**2) + (Y - center_y)**2 / (85**2)) <= 1.0

# Air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create right lung (elliptical, on right side of image)
# In radiological convention, right lung appears on left side of image
lung_cx, lung_cy = center_x + 40, center_y  # Right lung (patient's right = image left)
lung_rx, lung_ry = 50, 60  # Semi-axes

lung_mask = np.zeros((nx, ny, nz), dtype=bool)
for z in range(15, 85):  # Lung extent in z
    z_factor = 1.0 - 0.3 * ((z - 50) / 35)**2  # Taper at top and bottom
    current_rx = int(lung_rx * z_factor)
    current_ry = int(lung_ry * z_factor)
    if current_rx > 5 and current_ry > 5:
        slice_mask = ((X - lung_cx)**2 / (current_rx**2) + 
                      (Y - lung_cy)**2 / (current_ry**2)) <= 1.0
        lung_mask[:, :, z] = slice_mask & body_mask

# Fill lung with air-like HU values
ct_data[lung_mask] = np.random.normal(-700, 50, (np.sum(lung_mask),)).astype(np.int16)

# Create mediastinum/spine (central dense structure)
spine_cx, spine_cy = center_x, center_y + 40
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask & body_mask] = np.random.normal(400, 50, 
        (np.sum(spine_mask & body_mask),)).astype(np.int16)

# ============================================================
# Create lung segmentation WITH HOLES (vessels/airways)
# ============================================================
print("Creating lung segmentation with internal holes...")

# Start with the full lung mask
lung_seg = lung_mask.astype(np.int16)

# Add vessel-like holes (cylinders running through the lung)
# Pulmonary vessels appear as holes when segmenting just lung parenchyma
holes_created = 0

# Major vessels (larger tubes)
for i in range(8):
    # Random position within lung region
    vx = lung_cx + np.random.randint(-30, 30)
    vy = lung_cy + np.random.randint(-40, 40)
    vr = np.random.randint(3, 8)  # Vessel radius in voxels
    
    # Create cylindrical hole along z-axis
    for z in range(20, 80):
        vessel_mask = ((X - vx)**2 + (Y - vy)**2) <= vr**2
        hole_region = vessel_mask & lung_mask[:, :, z]
        holes_created += np.sum(hole_region)
        lung_seg[:, :, z][hole_region] = 0

# Smaller vessels/airways (scattered small holes)
for i in range(25):
    # Random spherical holes
    hx = lung_cx + np.random.randint(-35, 35)
    hy = lung_cy + np.random.randint(-45, 45)
    hz = np.random.randint(25, 75)
    hr = np.random.randint(2, 5)
    
    for dz in range(-hr, hr+1):
        z = hz + dz
        if 0 <= z < nz:
            for dx in range(-hr, hr+1):
                for dy in range(-hr, hr+1):
                    if dx**2 + dy**2 + dz**2 <= hr**2:
                        x, y = hx + dx, hy + dy
                        if 0 <= x < nx and 0 <= y < ny:
                            if lung_seg[x, y, z] > 0:
                                lung_seg[x, y, z] = 0
                                holes_created += 1

print(f"Created {holes_created} hole voxels")

# ============================================================
# Create ground truth (filled version)
# ============================================================
print("Creating ground truth filled segmentation...")

from scipy.ndimage import binary_closing

# The filled version is just the original lung mask
lung_filled = lung_mask.astype(np.int16)

# ============================================================
# Calculate initial statistics
# ============================================================
initial_volume_voxels = int(np.sum(lung_seg > 0))
filled_volume_voxels = int(np.sum(lung_filled > 0))
hole_voxels = filled_volume_voxels - initial_volume_voxels

voxel_volume_mm3 = float(np.prod(spacing))
initial_volume_ml = initial_volume_voxels * voxel_volume_mm3 / 1000.0
filled_volume_ml = filled_volume_voxels * voxel_volume_mm3 / 1000.0

# Calculate bounding box
nonzero = np.argwhere(lung_seg > 0)
if len(nonzero) > 0:
    bbox_min = nonzero.min(axis=0).tolist()
    bbox_max = nonzero.max(axis=0).tolist()
else:
    bbox_min = [0, 0, 0]
    bbox_max = [nx, ny, nz]

# Euler characteristic approximation (count connected components of holes)
hole_mask = lung_mask & (lung_seg == 0)
labeled_holes, num_holes = scipy_label(hole_mask)

print(f"Initial volume: {initial_volume_ml:.1f} mL")
print(f"Expected filled volume: {filled_volume_ml:.1f} mL")
print(f"Hole voxels: {hole_voxels}")
print(f"Number of hole regions: {num_holes}")

initial_stats = {
    "initial_volume_voxels": initial_volume_voxels,
    "initial_volume_ml": initial_volume_ml,
    "expected_filled_volume_voxels": filled_volume_voxels,
    "expected_filled_volume_ml": filled_volume_ml,
    "hole_voxels": hole_voxels,
    "num_hole_regions": num_holes,
    "volume_increase_expected_percent": 100.0 * hole_voxels / initial_volume_voxels if initial_volume_voxels > 0 else 0,
    "bounding_box_min": bbox_min,
    "bounding_box_max": bbox_max,
    "spacing_mm": list(spacing),
    "voxel_volume_mm3": voxel_volume_mm3,
    "segment_name": "RightLung"
}

# Save initial stats
stats_path = "/tmp/initial_segment_stats.json"
with open(stats_path, "w") as f:
    json.dump(initial_stats, f, indent=2)
print(f"Saved initial stats to {stats_path}")

# Also save to ground truth dir
gt_stats_path = os.path.join(gt_dir, "lung_initial_stats.json")
with open(gt_stats_path, "w") as f:
    json.dump(initial_stats, f, indent=2)

# ============================================================
# Save NIfTI files
# ============================================================
print("Saving files...")

# Save CT volume
ct_nii = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(data_dir, "chest_ct.nrrd")
nib.save(ct_nii, ct_path.replace('.nrrd', '.nii.gz'))
# Also save as nrrd for Slicer compatibility
os.system(f"cp {ct_path.replace('.nrrd', '.nii.gz')} {ct_path.replace('.nrrd', '.nii.gz')}")
print(f"Saved CT: {ct_path.replace('.nrrd', '.nii.gz')}")

# Save lung segmentation with holes
seg_nii = nib.Nifti1Image(lung_seg, affine)
seg_path = os.path.join(data_dir, "lung_with_holes.nii.gz")
nib.save(seg_nii, seg_path)
print(f"Saved segmentation: {seg_path}")

# Save ground truth filled segmentation
filled_nii = nib.Nifti1Image(lung_filled, affine)
filled_path = os.path.join(gt_dir, "lung_filled_reference.nii.gz")
nib.save(filled_nii, filled_path)
print(f"Saved ground truth: {filled_path}")

print("Data generation complete")
PYEOF

# Set permissions
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod -R 755 "$DATA_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Verify files were created
CT_FILE="$DATA_DIR/chest_ct.nii.gz"
SEG_FILE="$DATA_DIR/lung_with_holes.nii.gz"

if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not created"
    exit 1
fi

if [ ! -f "$SEG_FILE" ]; then
    echo "ERROR: Segmentation file not created"
    exit 1
fi

echo "CT file: $(ls -lh "$CT_FILE" | awk '{print $5}')"
echo "Segmentation file: $(ls -lh "$SEG_FILE" | awk '{print $5}')"

# ============================================================
# Create Python script to load data into Slicer
# ============================================================
LOAD_SCRIPT="/tmp/load_lung_data.py"
cat > "$LOAD_SCRIPT" << 'SLICER_SCRIPT'
import slicer
import os

data_dir = "/home/ga/Documents/SlicerData/LungHoles"
ct_path = os.path.join(data_dir, "chest_ct.nii.gz")
seg_path = os.path.join(data_dir, "lung_with_holes.nii.gz")

print("Loading chest CT...")
ct_node = slicer.util.loadVolume(ct_path)
if ct_node:
    ct_node.SetName("ChestCT")
    print(f"Loaded CT: {ct_node.GetName()}")
else:
    print("ERROR: Failed to load CT")

print("Loading lung segmentation...")
# Load as labelmap first, then convert to segmentation
labelmap_node = slicer.util.loadLabelVolume(seg_path)
if labelmap_node:
    labelmap_node.SetName("LungLabelmap")
    print(f"Loaded labelmap: {labelmap_node.GetName()}")
    
    # Create segmentation from labelmap
    seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    seg_node.SetName("LungSegmentation")
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmap_node, seg_node)
    
    # Rename the segment
    segmentation = seg_node.GetSegmentation()
    if segmentation.GetNumberOfSegments() > 0:
        segment_id = segmentation.GetNthSegmentID(0)
        segment = segmentation.GetSegment(segment_id)
        segment.SetName("RightLung")
        # Set a visible color
        segment.SetColor(0.2, 0.8, 0.2)  # Green
        print(f"Created segment: RightLung")
    
    # Remove temporary labelmap
    slicer.mrmlScene.RemoveNode(labelmap_node)
    
    # Set reference geometry
    seg_node.SetReferenceImageGeometryParameterFromVolumeNode(ct_node)
else:
    print("ERROR: Failed to load segmentation")

# Set up visualization
print("Setting up views...")

# Set CT window/level for lung viewing
display_node = ct_node.GetDisplayNode()
if display_node:
    display_node.SetAutoWindowLevel(False)
    display_node.SetWindow(1500)
    display_node.SetLevel(-500)

# Make segmentation visible
seg_display = seg_node.GetDisplayNode()
if seg_display:
    seg_display.SetVisibility(True)
    seg_display.SetOpacity2DFill(0.5)
    seg_display.SetOpacity2DOutline(1.0)

# Go to Segment Editor module
slicer.util.selectModule("SegmentEditor")

# Set the segmentation and master volume in Segment Editor
import slicer.util
editor_widget = slicer.modules.segmenteditor.widgetRepresentation().self()
if editor_widget:
    editor_widget.setSegmentationNode(seg_node)
    editor_widget.setSourceVolumeNode(ct_node)

# Center on the lung
slice_nodes = slicer.util.getNodesByClass("vtkMRMLSliceNode")
for slice_node in slice_nodes:
    slice_node.JumpSliceByCentering(0, 0, 125)  # Center z-coordinate

print("Setup complete - ready for hole filling task")
SLICER_SCRIPT

chmod 644 "$LOAD_SCRIPT"
chown ga:ga "$LOAD_SCRIPT"

# ============================================================
# Launch 3D Slicer
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for Slicer to start..."
wait_for_slicer 90

# Focus and maximize
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Load the data using Python script
echo "Loading data into Slicer..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script $LOAD_SCRIPT --no-splash" &
sleep 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Fill internal holes in the RightLung segmentation"
echo ""
echo "The lung segmentation has internal holes (dark spots) where"
echo "blood vessels and airways were excluded. Use the Segment Editor's"
echo "Smoothing effect with 'Closing (fill holes)' to fill them."
echo ""
echo "Steps:"
echo "1. Select 'RightLung' segment in Segment Editor"
echo "2. Click 'Smoothing' effect"
echo "3. Change Method to 'Closing (fill holes)'"
echo "4. Set kernel size to 3-5 mm"
echo "5. Click 'Apply'"
echo "6. Save to: ~/Documents/SlicerData/Exports/filled_lung_segment.seg.nrrd"
echo ""