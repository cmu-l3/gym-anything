#!/bin/bash
echo "=== Setting up Clean Segmentation Islands Task ==="

source /workspace/scripts/task_utils.sh

DATA_DIR="/home/ga/Documents/SlicerData/ChestCT"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean any previous results
rm -f "$EXPORT_DIR/lungs_cleaned.seg.nrrd" 2>/dev/null || true
rm -f /tmp/islands_task_result.json 2>/dev/null || true

# ============================================================
# Generate synthetic chest CT with noisy lung segmentation
# (or use real data if available)
# ============================================================

echo "Preparing chest CT data with noisy lung segmentation..."

# Check if CTChest sample exists
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
CTCHEST_FILE="$SAMPLE_DIR/CTChest.nrrd"

if [ -f "$CTCHEST_FILE" ]; then
    echo "Using existing CTChest sample data"
    cp "$CTCHEST_FILE" "$DATA_DIR/chest_ct.nrrd"
else
    echo "CTChest not found, generating synthetic chest CT..."
fi

# Generate the noisy lung segmentation with artifacts
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

from scipy.ndimage import label as scipy_label, binary_dilation, binary_erosion

data_dir = "/home/ga/Documents/SlicerData/ChestCT"
gt_dir = "/var/lib/slicer/ground_truth"
sample_ct = "/home/ga/Documents/SlicerData/SampleData/CTChest.nrrd"

np.random.seed(42)

# ============================================================
# Load or generate chest CT volume
# ============================================================
if os.path.exists(sample_ct):
    print(f"Loading CTChest from {sample_ct}")
    ct_nii = nib.load(sample_ct)
    ct_data = ct_nii.get_fdata()
    affine = ct_nii.affine
    spacing = ct_nii.header.get_zooms()[:3] if hasattr(ct_nii.header, 'get_zooms') else (1.0, 1.0, 1.0)
else:
    print("Generating synthetic chest CT volume...")
    # Create synthetic chest CT
    nx, ny, nz = 256, 256, 128
    spacing = (1.0, 1.0, 2.5)
    
    affine = np.eye(4)
    affine[0, 0] = spacing[0]
    affine[1, 1] = spacing[1]
    affine[2, 2] = spacing[2]
    
    ct_data = np.zeros((nx, ny, nz), dtype=np.float32)
    
    # Create body outline (elliptical)
    Y, X = np.ogrid[:nx, :ny]
    center_x, center_y = nx // 2, ny // 2
    body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (80**2)) <= 1.0
    
    # Fill with soft tissue
    ct_data[:] = np.random.normal(40, 15, (nx, ny, nz))
    
    # Air outside body
    for z in range(nz):
        ct_data[:, :, z][~body_mask] = -1000
    
    # Create lung regions (air-filled ellipses)
    # Right lung
    right_lung_cx, right_lung_cy = center_x + 40, center_y
    # Left lung  
    left_lung_cx, left_lung_cy = center_x - 40, center_y
    
    for z in range(20, nz - 20):
        z_factor = 1.0 - 0.5 * ((z - nz/2) / (nz/2))**2
        
        # Right lung
        right_mask = ((X - right_lung_cx)**2 / (35*z_factor)**2 + 
                      (Y - right_lung_cy)**2 / (50*z_factor)**2) <= 1.0
        ct_data[:, :, z][right_mask & body_mask] = np.random.normal(-850, 50, 
            (np.sum(right_mask & body_mask),))
        
        # Left lung
        left_mask = ((X - left_lung_cx)**2 / (35*z_factor)**2 + 
                     (Y - left_lung_cy)**2 / (50*z_factor)**2) <= 1.0
        ct_data[:, :, z][left_mask & body_mask] = np.random.normal(-850, 50,
            (np.sum(left_mask & body_mask),))

print(f"CT volume shape: {ct_data.shape}")

# ============================================================
# Create lung segmentation using thresholding
# ============================================================
print("Creating lung segmentation via thresholding...")

# Threshold for lung tissue (air)
lung_threshold = -500
lung_mask = ct_data < lung_threshold

# Basic cleanup - remove outside air
if ct_data.shape[0] > 100:
    # Keep only central region
    margin = 20
    for z in range(ct_data.shape[2]):
        # Find body boundary
        slice_body = ct_data[:, :, z] > -500
        if np.any(slice_body):
            # Only keep lung inside body
            lung_mask[:, :, z] = lung_mask[:, :, z] & binary_erosion(slice_body, iterations=5)

# ============================================================
# Add deliberate artifacts (small islands)
# ============================================================
print("Adding artifact islands to create noisy segmentation...")

noisy_lung_mask = lung_mask.copy()
artifact_count = 0
artifact_info = []

# Add random small spherical artifacts near lung boundaries
for _ in range(25):
    # Random position near lung region
    lung_coords = np.argwhere(lung_mask)
    if len(lung_coords) == 0:
        continue
    
    # Pick a random lung voxel and offset from it
    idx = np.random.randint(len(lung_coords))
    base = lung_coords[idx]
    
    # Offset to create artifact outside main lung
    offset = np.random.randint(-30, 30, size=3)
    artifact_center = base + offset
    
    # Clamp to valid range
    artifact_center = np.clip(artifact_center, 5, np.array(ct_data.shape) - 5)
    
    # Check if this would be outside the main lung
    if lung_mask[artifact_center[0], artifact_center[1], artifact_center[2]]:
        continue
    
    # Create small spherical artifact
    radius = np.random.randint(2, 6)
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                if dx**2 + dy**2 + dz**2 <= radius**2:
                    x = artifact_center[0] + dx
                    y = artifact_center[1] + dy
                    z = artifact_center[2] + dz
                    if (0 <= x < ct_data.shape[0] and 
                        0 <= y < ct_data.shape[1] and 
                        0 <= z < ct_data.shape[2]):
                        noisy_lung_mask[x, y, z] = True
    
    artifact_count += 1
    artifact_info.append({
        "center": artifact_center.tolist(),
        "radius": int(radius)
    })

print(f"Added {artifact_count} artifact islands")

# ============================================================
# Count connected components
# ============================================================
labeled_array, num_islands = scipy_label(noisy_lung_mask)
print(f"Total islands in noisy segmentation: {num_islands}")

# Calculate component sizes
component_sizes = []
for i in range(1, num_islands + 1):
    size = np.sum(labeled_array == i)
    component_sizes.append((i, size))

component_sizes.sort(key=lambda x: x[1], reverse=True)
print(f"Largest components: {component_sizes[:5]}")

# Count how many are "artifacts" (small)
small_threshold = 500  # voxels
main_components = [c for c in component_sizes if c[1] >= small_threshold]
artifact_components = [c for c in component_sizes if c[1] < small_threshold]

print(f"Main lung components (>={small_threshold} voxels): {len(main_components)}")
print(f"Artifact components (<{small_threshold} voxels): {len(artifact_components)}")

# ============================================================
# Save volumes
# ============================================================

# Save CT volume
ct_nii = nib.Nifti1Image(ct_data.astype(np.int16), affine)
ct_path = os.path.join(data_dir, "chest_ct.nii.gz")
nib.save(ct_nii, ct_path)
print(f"Saved CT volume to {ct_path}")

# Save noisy lung segmentation
seg_nii = nib.Nifti1Image(noisy_lung_mask.astype(np.int16), affine)
seg_path = os.path.join(data_dir, "lungs_noisy.nii.gz")
nib.save(seg_nii, seg_path)
print(f"Saved noisy segmentation to {seg_path}")

# ============================================================
# Save ground truth for verification
# ============================================================
total_volume = np.sum(noisy_lung_mask)
main_volume = sum(c[1] for c in main_components)

gt_data = {
    "original_island_count": num_islands,
    "main_component_count": len(main_components),
    "artifact_component_count": len(artifact_components),
    "total_voxels": int(total_volume),
    "main_structure_voxels": int(main_volume),
    "artifact_voxels": int(total_volume - main_volume),
    "voxel_spacing_mm": list(spacing) if isinstance(spacing, tuple) else spacing,
    "largest_components": [(int(c[0]), int(c[1])) for c in component_sizes[:5]],
    "artifacts_added": artifact_info[:10]  # First 10 artifacts
}

gt_path = os.path.join(gt_dir, "islands_ground_truth.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Saved ground truth to {gt_path}")

print("\n=== Data Preparation Complete ===")
print(f"CT volume: {ct_path}")
print(f"Noisy segmentation: {seg_path}")
print(f"Total islands: {num_islands}")
print(f"Expected cleaned islands: {len(main_components)}")
PYEOF

# Verify files were created
CT_FILE="$DATA_DIR/chest_ct.nii.gz"
SEG_FILE="$DATA_DIR/lungs_noisy.nii.gz"

if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not created"
    exit 1
fi

if [ ! -f "$SEG_FILE" ]; then
    echo "ERROR: Segmentation not created"
    exit 1
fi

echo "Data files created:"
ls -la "$DATA_DIR"

# Set permissions
chown -R ga:ga "$DATA_DIR"
chmod 755 "$GROUND_TRUTH_DIR"

# ============================================================
# Launch 3D Slicer and load the data
# ============================================================
echo "Launching 3D Slicer with chest CT and segmentation..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load data and set up Segment Editor
cat > /tmp/load_islands_task.py << 'LOADPY'
import slicer
import os

# Load CT volume
ct_path = "/home/ga/Documents/SlicerData/ChestCT/chest_ct.nii.gz"
seg_path = "/home/ga/Documents/SlicerData/ChestCT/lungs_noisy.nii.gz"

print("Loading CT volume...")
ct_node = slicer.util.loadVolume(ct_path)
if ct_node:
    print(f"Loaded CT: {ct_node.GetName()}")
else:
    print("ERROR: Failed to load CT volume")

print("Loading segmentation as labelmap...")
seg_node = slicer.util.loadLabelVolume(seg_path)
if seg_node:
    print(f"Loaded segmentation labelmap: {seg_node.GetName()}")
    
    # Convert labelmap to segmentation
    print("Converting to segmentation node...")
    segmentation_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    segmentation_node.SetName("LungsSegmentation")
    
    # Import labelmap
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(seg_node, segmentation_node)
    
    # Rename the segment
    segmentation = segmentation_node.GetSegmentation()
    if segmentation.GetNumberOfSegments() > 0:
        segment_id = segmentation.GetNthSegmentID(0)
        segment = segmentation.GetSegment(segment_id)
        segment.SetName("Lungs")
        segment.SetColor(0.0, 0.5, 1.0)  # Blue color
        print("Renamed segment to 'Lungs'")
    
    # Set as reference geometry
    segmentation_node.SetReferenceImageGeometryParameterFromVolumeNode(ct_node)
    
    # Remove the temporary labelmap
    slicer.mrmlScene.RemoveNode(seg_node)
else:
    print("ERROR: Failed to load segmentation")

# Set up views
print("Configuring views...")
slicer.util.setSliceViewerLayers(background=ct_node)

# Center views on data
slicer.util.resetSliceViews()

# Switch to Segment Editor module
print("Switching to Segment Editor...")
slicer.util.selectModule("SegmentEditor")

print("Setup complete!")
LOADPY

# Launch Slicer with the setup script
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_islands_task.py > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start and load data..."
sleep 15

# Wait for Slicer window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/islands_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Clean the lung segmentation using the Islands effect"
echo ""
echo "The 'Lungs' segment contains many small artifact islands."
echo "Use Segment Editor > Islands effect to remove them."
echo ""
echo "Save cleaned segmentation to:"
echo "  ~/Documents/SlicerData/Exports/lungs_cleaned.seg.nrrd"
echo ""