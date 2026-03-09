#!/bin/bash
echo "=== Setting up Smooth Surface Model Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
INPUT_MODEL="$BRATS_DIR/TumorModel_Rough.vtk"
OUTPUT_MODEL="$BRATS_DIR/TumorModel_Smoothed.vtk"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Clean any previous task outputs
rm -f "$OUTPUT_MODEL" 2>/dev/null || true
rm -f /tmp/smooth_task_result.json 2>/dev/null || true

# ============================================================
# Prepare BraTS data if not exists
# ============================================================
echo "Preparing BraTS data..."
export GROUND_TRUTH_DIR BRATS_DIR
/workspace/scripts/prepare_brats_data.sh "BraTS2021_00000" 2>/dev/null || {
    echo "BraTS download failed, creating synthetic brain tumor data..."
}

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using sample ID: $SAMPLE_ID"

# ============================================================
# Create rough tumor model from segmentation
# ============================================================
echo "Creating rough tumor surface model..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
for pkg in ['nibabel', 'vtk']:
    try:
        __import__(pkg)
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", pkg])

import nibabel as nib
import vtk
from vtk.util import numpy_support

brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
sample_id = open("/tmp/brats_sample_id").read().strip() if os.path.exists("/tmp/brats_sample_id") else "BraTS2021_00000"

# Find segmentation file
seg_paths = [
    f"{gt_dir}/{sample_id}_seg.nii.gz",
    f"{brats_dir}/{sample_id}/{sample_id}_seg.nii.gz",
]

seg_path = None
for p in seg_paths:
    if os.path.exists(p):
        seg_path = p
        break

if seg_path is None:
    # Create synthetic segmentation if none exists
    print("Creating synthetic tumor segmentation...")
    
    # Create a simple ellipsoid tumor
    shape = (128, 128, 80)
    seg_data = np.zeros(shape, dtype=np.int16)
    
    # Create tumor ellipsoid
    center = np.array([64, 64, 40])
    radii = np.array([20, 15, 12])
    
    for x in range(shape[0]):
        for y in range(shape[1]):
            for z in range(shape[2]):
                dist = np.sqrt(
                    ((x - center[0]) / radii[0])**2 +
                    ((y - center[1]) / radii[1])**2 +
                    ((z - center[2]) / radii[2])**2
                )
                if dist <= 1.0:
                    seg_data[x, y, z] = 1
    
    # Add some irregularity to make it more tumor-like
    np.random.seed(42)
    noise = np.random.normal(0, 0.3, shape)
    
    for x in range(shape[0]):
        for y in range(shape[1]):
            for z in range(shape[2]):
                dist = np.sqrt(
                    ((x - center[0]) / radii[0])**2 +
                    ((y - center[1]) / radii[1])**2 +
                    ((z - center[2]) / radii[2])**2
                )
                threshold = 1.0 + noise[x, y, z] * 0.2
                if dist <= threshold and dist > 0.7:
                    if np.random.random() > 0.3:
                        seg_data[x, y, z] = 1
    
    affine = np.eye(4)
    affine[0, 0] = affine[1, 1] = affine[2, 2] = 1.0
    
    seg_nii = nib.Nifti1Image(seg_data, affine)
    seg_path = f"{gt_dir}/synthetic_seg.nii.gz"
    os.makedirs(gt_dir, exist_ok=True)
    nib.save(seg_nii, seg_path)
    print(f"Synthetic segmentation saved to {seg_path}")
else:
    print(f"Loading segmentation from {seg_path}")

# Load segmentation
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int16)
affine = seg_nii.affine
voxel_dims = seg_nii.header.get_zooms()[:3]

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel dimensions: {voxel_dims}")

# Create binary tumor mask (combine all tumor labels for BraTS: 1, 2, 4)
tumor_mask = (seg_data > 0).astype(np.uint8)
tumor_voxels = np.sum(tumor_mask)
print(f"Tumor voxels: {tumor_voxels}")

if tumor_voxels < 100:
    print("ERROR: Tumor too small or not found!")
    sys.exit(1)

# Convert to VTK image data
vtk_data = vtk.vtkImageData()
vtk_data.SetDimensions(seg_data.shape[0], seg_data.shape[1], seg_data.shape[2])
vtk_data.SetSpacing(float(voxel_dims[0]), float(voxel_dims[1]), float(voxel_dims[2]))
vtk_data.SetOrigin(0, 0, 0)

# Convert numpy array to VTK array
flat_data = tumor_mask.flatten(order='F')  # Fortran order for VTK
vtk_array = numpy_support.numpy_to_vtk(flat_data, deep=True, array_type=vtk.VTK_UNSIGNED_CHAR)
vtk_data.GetPointData().SetScalars(vtk_array)

# Apply marching cubes WITHOUT smoothing to create rough model
print("Generating rough surface model (no smoothing)...")
marching_cubes = vtk.vtkMarchingCubes()
marching_cubes.SetInputData(vtk_data)
marching_cubes.SetValue(0, 0.5)  # Isovalue for binary mask
marching_cubes.ComputeNormalsOn()
marching_cubes.Update()

rough_polydata = marching_cubes.GetOutput()
num_points = rough_polydata.GetNumberOfPoints()
num_cells = rough_polydata.GetNumberOfCells()

print(f"Rough model: {num_points} points, {num_cells} polygons")

if num_points < 100 or num_cells < 100:
    print("ERROR: Model generation failed - too few vertices!")
    sys.exit(1)

# Save rough model
output_path = f"{brats_dir}/TumorModel_Rough.vtk"
writer = vtk.vtkPolyDataWriter()
writer.SetFileName(output_path)
writer.SetInputData(rough_polydata)
writer.Write()
print(f"Rough model saved to {output_path}")

# Calculate baseline roughness metrics
def calculate_roughness_metrics(polydata):
    """Calculate surface roughness using curvature variance."""
    # Compute curvatures
    curvature_filter = vtk.vtkCurvatures()
    curvature_filter.SetInputData(polydata)
    curvature_filter.SetCurvatureTypeToMean()
    curvature_filter.Update()
    
    curvature_data = curvature_filter.GetOutput()
    curvature_array = curvature_data.GetPointData().GetScalars()
    
    if curvature_array is None:
        return {"curvature_variance": 0, "curvature_mean": 0, "curvature_std": 0}
    
    # Convert to numpy
    curvatures = numpy_support.vtk_to_numpy(curvature_array)
    
    # Filter out NaN/Inf values
    valid_curvatures = curvatures[np.isfinite(curvatures)]
    
    if len(valid_curvatures) == 0:
        return {"curvature_variance": 0, "curvature_mean": 0, "curvature_std": 0}
    
    return {
        "curvature_variance": float(np.var(valid_curvatures)),
        "curvature_mean": float(np.mean(valid_curvatures)),
        "curvature_std": float(np.std(valid_curvatures)),
        "curvature_abs_mean": float(np.mean(np.abs(valid_curvatures)))
    }

def calculate_shape_metrics(polydata):
    """Calculate shape metrics: volume, surface area, bounds."""
    # Calculate volume
    mass_props = vtk.vtkMassProperties()
    mass_props.SetInputData(polydata)
    mass_props.Update()
    
    volume = mass_props.GetVolume()
    surface_area = mass_props.GetSurfaceArea()
    
    # Get bounds
    bounds = polydata.GetBounds()
    
    return {
        "volume_mm3": float(volume),
        "surface_area_mm2": float(surface_area),
        "bounds": list(bounds),
        "bounds_size": [
            bounds[1] - bounds[0],
            bounds[3] - bounds[2],
            bounds[5] - bounds[4]
        ],
        "polygon_count": polydata.GetNumberOfCells(),
        "point_count": polydata.GetNumberOfPoints()
    }

# Calculate and save baseline metrics
roughness = calculate_roughness_metrics(rough_polydata)
shape = calculate_shape_metrics(rough_polydata)

baseline_metrics = {
    "model_path": output_path,
    "sample_id": sample_id,
    "roughness": roughness,
    "shape": shape
}

# Save baseline metrics for verification
baseline_path = f"{gt_dir}/baseline_model_metrics.json"
with open(baseline_path, "w") as f:
    json.dump(baseline_metrics, f, indent=2)

print(f"\nBaseline metrics saved to {baseline_path}")
print(f"  Curvature variance: {roughness['curvature_variance']:.6f}")
print(f"  Volume: {shape['volume_mm3']:.2f} mm³")
print(f"  Surface area: {shape['surface_area_mm2']:.2f} mm²")
print(f"  Polygon count: {shape['polygon_count']}")

# Also save a copy of the rough model to ground truth for comparison
import shutil
shutil.copy(output_path, f"{gt_dir}/TumorModel_Rough_baseline.vtk")

print("\nSetup complete!")
PYEOF

# Verify model was created
if [ ! -f "$INPUT_MODEL" ]; then
    echo "ERROR: Failed to create rough tumor model"
    exit 1
fi

echo "Rough model created: $INPUT_MODEL"
ls -la "$INPUT_MODEL"

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true

# ============================================================
# Launch 3D Slicer with the model loaded
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load model and set up scene
cat > /tmp/setup_smooth_task.py << 'SLICERPY'
import slicer
import os

brats_dir = "/home/ga/Documents/SlicerData/BraTS"
model_path = os.path.join(brats_dir, "TumorModel_Rough.vtk")

print(f"Loading model from {model_path}")

# Load the rough model
if os.path.exists(model_path):
    success, model_node = slicer.util.loadModel(model_path, returnNode=True)
    if success and model_node:
        model_node.SetName("TumorModel_Rough")
        
        # Set display properties to show artifacts
        display = model_node.GetDisplayNode()
        if display:
            display.SetColor(0.9, 0.3, 0.3)  # Red color
            display.SetOpacity(1.0)
            display.SetVisibility(True)
        
        print(f"Model loaded: {model_node.GetName()}")
        print(f"  Points: {model_node.GetPolyData().GetNumberOfPoints()}")
        print(f"  Polygons: {model_node.GetPolyData().GetNumberOfCells()}")
    else:
        print("ERROR: Failed to load model")
else:
    print(f"ERROR: Model file not found at {model_path}")

# Reset 3D view to show the model
layoutManager = slicer.app.layoutManager()
threeDWidget = layoutManager.threeDWidget(0)
threeDView = threeDWidget.threeDView()
threeDView.resetFocalPoint()
threeDView.resetCamera()

# Switch to 3D-only layout
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutOneUp3DView)

print("Scene setup complete - model ready for smoothing")
SLICERPY

# Launch Slicer with setup script
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/setup_smooth_task.py > /tmp/slicer_setup.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

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
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Smooth the rough tumor surface model"
echo ""
echo "Input model: $INPUT_MODEL (loaded as 'TumorModel_Rough')"
echo "Output file: $OUTPUT_MODEL"
echo ""
echo "Steps:"
echo "1. Go to Surface Toolbox module (Modules > Surface Models > Surface Toolbox)"
echo "2. Select 'TumorModel_Rough' as input"
echo "3. Apply Laplacian or Windowed Sinc smoothing"
echo "4. Save output as 'TumorModel_Smoothed.vtk'"
echo ""