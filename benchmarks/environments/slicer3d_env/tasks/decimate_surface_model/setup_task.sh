#!/bin/bash
echo "=== Setting up Surface Model Decimation Task ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure directories exist
mkdir -p /home/ga/Documents/SlicerData/Exports
mkdir -p /home/ga/Documents/SlicerData/Models
mkdir -p /var/lib/slicer/ground_truth
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true

# Clean any previous task artifacts
rm -f /home/ga/Documents/SlicerData/Exports/brain_decimated.vtk 2>/dev/null || true
rm -f /tmp/decimate_result.json 2>/dev/null || true

# Install required Python packages
echo "Ensuring Python dependencies..."
pip3 install -q numpy nibabel scipy scikit-image vtk 2>/dev/null || true

# Prepare BraTS data if not already present
echo "Preparing brain MRI data..."
export SAMPLE_ID="BraTS2021_00000"

# Try to run the BraTS preparation script
if [ -f /workspace/scripts/prepare_brats_data.sh ]; then
    /workspace/scripts/prepare_brats_data.sh "$SAMPLE_ID" 2>/dev/null || echo "BraTS download skipped or failed"
fi

# Generate the high-poly brain surface model
echo "Generating high-resolution brain surface model..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    from skimage import measure
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scikit-image"])
    from skimage import measure

try:
    import vtk
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "vtk"])
    import vtk

from scipy.ndimage import binary_fill_holes, binary_dilation, binary_erosion, gaussian_filter

# Paths
brats_dir = "/home/ga/Documents/SlicerData/BraTS"
gt_dir = "/var/lib/slicer/ground_truth"
model_dir = "/home/ga/Documents/SlicerData/Models"
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")

os.makedirs(model_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

# Try to find the BraTS FLAIR volume
flair_path = None
for search_path in [
    f"{brats_dir}/{sample_id}/{sample_id}_flair.nii.gz",
    f"{brats_dir}/{sample_id}_flair.nii.gz",
    f"{brats_dir}/BraTS2021_00000/BraTS2021_00000_flair.nii.gz"
]:
    if os.path.exists(search_path):
        flair_path = search_path
        break

if flair_path and os.path.exists(flair_path):
    print(f"Loading FLAIR volume: {flair_path}")
    nii = nib.load(flair_path)
    data = nii.get_fdata()
    spacing = nii.header.get_zooms()[:3]
    
    # Create brain mask via thresholding
    threshold = np.percentile(data[data > 0], 15)
    brain_mask = data > threshold
    
    # Fill holes and clean up
    brain_mask = binary_fill_holes(brain_mask)
    brain_mask = binary_erosion(brain_mask, iterations=1)
    brain_mask = binary_dilation(brain_mask, iterations=1)
    
    print(f"Brain mask created from real MRI data")
else:
    print("BraTS data not found, generating synthetic brain volume...")
    # Generate synthetic brain-shaped volume
    np.random.seed(42)
    shape = (160, 200, 160)
    spacing = (1.0, 1.0, 1.0)
    
    # Create brain-like ellipsoid with surface detail
    z, y, x = np.ogrid[:shape[0], :shape[1], :shape[2]]
    center = np.array(shape) / 2
    
    # Main brain ellipsoid
    brain_dist = ((x - center[2])/60)**2 + ((y - center[1])/75)**2 + ((z - center[0])/55)**2
    brain_mask = brain_dist < 1.0
    
    # Add sulci-like surface detail using noise
    noise = np.random.randn(*shape) * 0.15
    noise = gaussian_filter(noise, sigma=3)
    
    # Modulate the surface
    surface_dist = np.sqrt(brain_dist)
    brain_mask = (surface_dist + noise * 0.3) < 1.0
    
    # Add ventricle-like cavity
    vent_dist = ((x - center[2])/15)**2 + ((y - center[1] - 20)/40)**2 + ((z - center[0])/12)**2
    ventricle = vent_dist < 1.0
    brain_mask = brain_mask & ~ventricle

print(f"Brain mask shape: {brain_mask.shape}")
print(f"Brain voxels: {np.sum(brain_mask)}")
print(f"Spacing: {spacing}")

# Generate surface mesh using marching cubes with step_size=1 for max polygons
print("Running marching cubes for high-res surface...")
verts, faces, normals, values = measure.marching_cubes(
    brain_mask.astype(float), 
    level=0.5,
    spacing=spacing,
    step_size=1
)

print(f"Initial mesh: {len(verts)} vertices, {len(faces)} faces")

# Create VTK polydata
points = vtk.vtkPoints()
for v in verts:
    points.InsertNextPoint(float(v[0]), float(v[1]), float(v[2]))

polys = vtk.vtkCellArray()
for f in faces:
    polys.InsertNextCell(3)
    polys.InsertCellPoint(int(f[0]))
    polys.InsertCellPoint(int(f[1]))
    polys.InsertCellPoint(int(f[2]))

polydata = vtk.vtkPolyData()
polydata.SetPoints(points)
polydata.SetPolys(polys)

# Compute normals for better visualization
normals_filter = vtk.vtkPolyDataNormals()
normals_filter.SetInputData(polydata)
normals_filter.ComputePointNormalsOn()
normals_filter.ComputeCellNormalsOn()
normals_filter.SplittingOff()
normals_filter.Update()

final_polydata = normals_filter.GetOutput()
num_polys = final_polydata.GetNumberOfPolys()
print(f"After normals: {num_polys} polygons")

# If polygon count is too low, subdivide to increase
target_min_polys = 400000
if num_polys < target_min_polys:
    print(f"Subdividing to increase polygon count (target: {target_min_polys})...")
    subdivide = vtk.vtkLoopSubdivisionFilter()
    subdivide.SetInputData(final_polydata)
    subdivide.SetNumberOfSubdivisions(1)
    subdivide.Update()
    final_polydata = subdivide.GetOutput()
    num_polys = final_polydata.GetNumberOfPolys()
    print(f"After subdivision: {num_polys} polygons")

# If still not enough, subdivide again
if num_polys < target_min_polys:
    print("Second subdivision pass...")
    subdivide2 = vtk.vtkLoopSubdivisionFilter()
    subdivide2.SetInputData(final_polydata)
    subdivide2.SetNumberOfSubdivisions(1)
    subdivide2.Update()
    final_polydata = subdivide2.GetOutput()
    num_polys = final_polydata.GetNumberOfPolys()
    print(f"After second subdivision: {num_polys} polygons")

# Save the high-res model
output_path = os.path.join(model_dir, "brain_highres.vtk")
writer = vtk.vtkPolyDataWriter()
writer.SetFileName(output_path)
writer.SetInputData(final_polydata)
writer.SetFileTypeToASCII()
writer.Write()
print(f"Saved high-res model: {output_path}")

# Get file size
file_size = os.path.getsize(output_path)
print(f"File size: {file_size / 1024 / 1024:.2f} MB")

# Get bounding box
bounds = final_polydata.GetBounds()
print(f"Bounding box: X[{bounds[0]:.1f}, {bounds[1]:.1f}], Y[{bounds[2]:.1f}, {bounds[3]:.1f}], Z[{bounds[4]:.1f}, {bounds[5]:.1f}]")

# Save ground truth info
gt_info = {
    "original_model": output_path,
    "original_polygons": num_polys,
    "original_vertices": final_polydata.GetNumberOfPoints(),
    "original_file_size_bytes": file_size,
    "bounding_box": list(bounds),
    "expected_output": "/home/ga/Documents/SlicerData/Exports/brain_decimated.vtk",
    "minimum_reduction_percent": 50,
    "target_max_polygons": num_polys // 2
}

gt_path = os.path.join(gt_dir, "decimate_task_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_info, f, indent=2)
print(f"Ground truth saved: {gt_path}")

print(f"\n=== Model Generation Complete ===")
print(f"Original polygons: {num_polys}")
print(f"Target after decimation: < {num_polys // 2}")
PYEOF

# Verify model was created
MODEL_PATH="/home/ga/Documents/SlicerData/Models/brain_highres.vtk"
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Failed to create brain model"
    exit 1
fi

MODEL_SIZE=$(stat -c%s "$MODEL_PATH" 2>/dev/null || echo "0")
echo "Created brain model: $(echo "scale=2; $MODEL_SIZE/1024/1024" | bc 2>/dev/null || echo "$MODEL_SIZE bytes")"

# Set permissions
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true
chmod 644 "$MODEL_PATH" 2>/dev/null || true
chmod 700 /var/lib/slicer/ground_truth 2>/dev/null || true

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load model in Slicer
cat > /tmp/load_brain_model.py << 'LOADPY'
import slicer
import os

model_path = "/home/ga/Documents/SlicerData/Models/brain_highres.vtk"
print(f"Loading model: {model_path}")

try:
    success, model_node = slicer.util.loadModel(model_path, returnNode=True)
    
    if success and model_node:
        print(f"Loaded model: {model_node.GetName()}")
        polydata = model_node.GetPolyData()
        if polydata:
            print(f"Polygons: {polydata.GetNumberOfPolys()}")
            print(f"Vertices: {polydata.GetNumberOfPoints()}")
        
        # Set display properties for visibility
        display = model_node.GetDisplayNode()
        if display:
            display.SetColor(0.9, 0.75, 0.65)  # Skin-like color
            display.SetOpacity(1.0)
            display.SetVisibility(True)
        
        # Reset 3D view to show model
        layoutManager = slicer.app.layoutManager()
        if layoutManager:
            threeDWidget = layoutManager.threeDWidget(0)
            if threeDWidget:
                threeDView = threeDWidget.threeDView()
                threeDView.resetFocalPoint()
                threeDView.resetCamera()
        
        print("Model loaded and displayed successfully")
    else:
        print("ERROR: Failed to load model")
except Exception as e:
    print(f"ERROR: {e}")
LOADPY

# Launch Slicer with the model
echo "Launching 3D Slicer with brain model..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Slicer
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer \
    --python-script /tmp/load_brain_model.py \
    "$MODEL_PATH" \
    > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to fully load..."
sleep 15

# Wait for window to appear
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null && DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for model to render
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo "A high-resolution brain surface model is loaded in 3D Slicer."
echo ""
echo "Original model: /home/ga/Documents/SlicerData/Models/brain_highres.vtk"
echo ""
echo "YOUR TASK:"
echo "1. Use Surface Toolbox module to decimate the model (reduce by ≥50%)"
echo "2. Save the decimated model to: /home/ga/Documents/SlicerData/Exports/brain_decimated.vtk"
echo ""
echo "To find Surface Toolbox: Modules menu → Surface Models → Surface Toolbox"