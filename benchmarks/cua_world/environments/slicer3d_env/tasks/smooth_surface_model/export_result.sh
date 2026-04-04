#!/bin/bash
echo "=== Exporting Smooth Surface Model Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
INPUT_MODEL="$BRATS_DIR/TumorModel_Rough.vtk"
OUTPUT_MODEL="$BRATS_DIR/TumorModel_Smoothed.vtk"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Try to export smoothed model from Slicer scene
# ============================================================
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Exporting models from Slicer scene..."
    
    cat > /tmp/export_smoothed.py << 'PYEOF'
import slicer
import os

brats_dir = "/home/ga/Documents/SlicerData/BraTS"

# Find all model nodes
model_nodes = slicer.util.getNodesByClass("vtkMRMLModelNode")
print(f"Found {len(model_nodes)} model nodes")

smoothed_found = False
for node in model_nodes:
    name = node.GetName().lower()
    print(f"  Model: {node.GetName()}")
    
    # Look for smoothed model
    if "smooth" in name or "output" in name:
        output_path = os.path.join(brats_dir, "TumorModel_Smoothed.vtk")
        success = slicer.util.saveNode(node, output_path)
        if success:
            print(f"  -> Saved smoothed model to {output_path}")
            smoothed_found = True
        break

# If no explicitly named smoothed model, check for any model that's different from rough
if not smoothed_found:
    for node in model_nodes:
        name = node.GetName()
        if "rough" not in name.lower() and "smooth" not in name.lower():
            # This might be the output model
            output_path = os.path.join(brats_dir, "TumorModel_Smoothed.vtk")
            success = slicer.util.saveNode(node, output_path)
            if success:
                print(f"  -> Saved model '{name}' as smoothed model to {output_path}")
                smoothed_found = True
                break

if not smoothed_found:
    print("WARNING: No smoothed model found in scene")
PYEOF

    # Run export script
    DISPLAY=:1 timeout 30 /opt/Slicer/Slicer --python-script /tmp/export_smoothed.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# ============================================================
# Check for output model and calculate metrics
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_MTIME="0"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_MODEL" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_MODEL" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_MODEL" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Smoothed model found: $OUTPUT_MODEL"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME (task started: $TASK_START)"
fi

# Also check for alternative output locations
ALT_OUTPUTS=(
    "$BRATS_DIR/smoothed.vtk"
    "$BRATS_DIR/output.vtk"
    "$BRATS_DIR/TumorModel_Smoothed.stl"
    "/home/ga/TumorModel_Smoothed.vtk"
    "/home/ga/Documents/TumorModel_Smoothed.vtk"
)

for alt in "${ALT_OUTPUTS[@]}"; do
    if [ -f "$alt" ] && [ "$OUTPUT_EXISTS" = "false" ]; then
        echo "Found alternative output: $alt"
        cp "$alt" "$OUTPUT_MODEL" 2>/dev/null || true
        if [ -f "$OUTPUT_MODEL" ]; then
            OUTPUT_EXISTS="true"
            OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_MODEL" 2>/dev/null || echo "0")
            OUTPUT_SIZE=$(stat -c %s "$OUTPUT_MODEL" 2>/dev/null || echo "0")
            FILE_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

# ============================================================
# Calculate metrics for both models
# ============================================================
echo "Calculating model metrics..."

python3 << 'PYEOF'
import os
import sys
import json

# Ensure VTK is available
try:
    import vtk
    from vtk.util import numpy_support
    import numpy as np
except ImportError:
    print("VTK not available for metrics calculation")
    sys.exit(0)

brats_dir = "/home/ga/Documents/SlicerData/BraTS"
gt_dir = "/var/lib/slicer/ground_truth"
input_model_path = f"{brats_dir}/TumorModel_Rough.vtk"
output_model_path = f"{brats_dir}/TumorModel_Smoothed.vtk"

def load_polydata(filepath):
    """Load VTK polydata from file."""
    if not os.path.exists(filepath):
        return None
    
    reader = vtk.vtkPolyDataReader()
    reader.SetFileName(filepath)
    reader.Update()
    return reader.GetOutput()

def calculate_roughness_metrics(polydata):
    """Calculate surface roughness using curvature variance."""
    if polydata is None or polydata.GetNumberOfPoints() == 0:
        return None
    
    # Compute curvatures
    curvature_filter = vtk.vtkCurvatures()
    curvature_filter.SetInputData(polydata)
    curvature_filter.SetCurvatureTypeToMean()
    curvature_filter.Update()
    
    curvature_data = curvature_filter.GetOutput()
    curvature_array = curvature_data.GetPointData().GetScalars()
    
    if curvature_array is None:
        return {"curvature_variance": 0, "curvature_mean": 0, "curvature_std": 0}
    
    curvatures = numpy_support.vtk_to_numpy(curvature_array)
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
    if polydata is None or polydata.GetNumberOfPoints() == 0:
        return None
    
    # Calculate volume
    mass_props = vtk.vtkMassProperties()
    mass_props.SetInputData(polydata)
    mass_props.Update()
    
    volume = mass_props.GetVolume()
    surface_area = mass_props.GetSurfaceArea()
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

# Load and analyze original model
original_polydata = load_polydata(input_model_path)
original_roughness = None
original_shape = None

if original_polydata:
    original_roughness = calculate_roughness_metrics(original_polydata)
    original_shape = calculate_shape_metrics(original_polydata)
    print(f"Original model: {original_shape['polygon_count']} polygons")
    print(f"  Curvature variance: {original_roughness['curvature_variance']:.6f}")
    print(f"  Volume: {original_shape['volume_mm3']:.2f} mm³")

# Load and analyze smoothed model
smoothed_polydata = load_polydata(output_model_path)
smoothed_roughness = None
smoothed_shape = None

if smoothed_polydata:
    smoothed_roughness = calculate_roughness_metrics(smoothed_polydata)
    smoothed_shape = calculate_shape_metrics(smoothed_polydata)
    print(f"Smoothed model: {smoothed_shape['polygon_count']} polygons")
    print(f"  Curvature variance: {smoothed_roughness['curvature_variance']:.6f}")
    print(f"  Volume: {smoothed_shape['volume_mm3']:.2f} mm³")

# Calculate improvement metrics
improvement = {}
if original_roughness and smoothed_roughness and original_roughness['curvature_variance'] > 0:
    roughness_reduction = (
        (original_roughness['curvature_variance'] - smoothed_roughness['curvature_variance']) 
        / original_roughness['curvature_variance'] * 100
    )
    improvement['roughness_reduction_percent'] = float(roughness_reduction)
    print(f"Roughness reduction: {roughness_reduction:.1f}%")

if original_shape and smoothed_shape and original_shape['volume_mm3'] > 0:
    volume_change = abs(
        (smoothed_shape['volume_mm3'] - original_shape['volume_mm3']) 
        / original_shape['volume_mm3'] * 100
    )
    improvement['volume_change_percent'] = float(volume_change)
    print(f"Volume change: {volume_change:.1f}%")
    
    # Check bounds change
    orig_size = original_shape['bounds_size']
    smooth_size = smoothed_shape['bounds_size']
    max_bounds_change = 0
    for i in range(3):
        if orig_size[i] > 0:
            change = abs(smooth_size[i] - orig_size[i]) / orig_size[i] * 100
            max_bounds_change = max(max_bounds_change, change)
    improvement['bounds_change_percent'] = float(max_bounds_change)
    print(f"Max bounds change: {max_bounds_change:.1f}%")

if smoothed_shape:
    improvement['polygon_retention_percent'] = (
        smoothed_shape['polygon_count'] / original_shape['polygon_count'] * 100
        if original_shape and original_shape['polygon_count'] > 0 else 0
    )

# Save metrics for verification
metrics = {
    "original_model": {
        "exists": original_polydata is not None,
        "roughness": original_roughness,
        "shape": original_shape
    },
    "smoothed_model": {
        "exists": smoothed_polydata is not None,
        "roughness": smoothed_roughness,
        "shape": smoothed_shape
    },
    "improvement": improvement
}

metrics_path = "/tmp/model_metrics.json"
with open(metrics_path, "w") as f:
    json.dump(metrics, f, indent=2)

print(f"\nMetrics saved to {metrics_path}")
PYEOF

# ============================================================
# Create result JSON
# ============================================================
echo "Creating result JSON..."

# Load calculated metrics
METRICS_JSON=$(cat /tmp/model_metrics.json 2>/dev/null || echo "{}")

# Extract key values
ROUGHNESS_REDUCTION=$(echo "$METRICS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('improvement',{}).get('roughness_reduction_percent', 0))" 2>/dev/null || echo "0")
VOLUME_CHANGE=$(echo "$METRICS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('improvement',{}).get('volume_change_percent', 0))" 2>/dev/null || echo "0")
BOUNDS_CHANGE=$(echo "$METRICS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('improvement',{}).get('bounds_change_percent', 0))" 2>/dev/null || echo "0")
POLYGON_COUNT=$(echo "$METRICS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('smoothed_model',{}).get('shape',{}).get('polygon_count', 0))" 2>/dev/null || echo "0")
ORIG_CURV_VAR=$(echo "$METRICS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('original_model',{}).get('roughness',{}).get('curvature_variance', 0))" 2>/dev/null || echo "0")
SMOOTH_CURV_VAR=$(echo "$METRICS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('smoothed_model',{}).get('roughness',{}).get('curvature_variance', 0))" 2>/dev/null || echo "0")

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "input_model_exists": $([ -f "$INPUT_MODEL" ] && echo "true" || echo "false"),
    "output_model_exists": $OUTPUT_EXISTS,
    "output_model_path": "$OUTPUT_MODEL",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "metrics": {
        "roughness_reduction_percent": $ROUGHNESS_REDUCTION,
        "volume_change_percent": $VOLUME_CHANGE,
        "bounds_change_percent": $BOUNDS_CHANGE,
        "smoothed_polygon_count": $POLYGON_COUNT,
        "original_curvature_variance": $ORIG_CURV_VAR,
        "smoothed_curvature_variance": $SMOOTH_CURV_VAR
    },
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/smooth_task_result.json 2>/dev/null || sudo rm -f /tmp/smooth_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/smooth_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/smooth_task_result.json
chmod 666 /tmp/smooth_task_result.json 2>/dev/null || sudo chmod 666 /tmp/smooth_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/smooth_task_result.json:"
cat /tmp/smooth_task_result.json
echo ""
echo "=== Export Complete ==="