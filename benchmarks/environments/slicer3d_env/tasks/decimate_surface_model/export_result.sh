#!/bin/bash
echo "=== Exporting Decimate Task Results ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Define paths
EXPECTED_OUTPUT="/home/ga/Documents/SlicerData/Exports/brain_decimated.vtk"
ORIGINAL_MODEL="/home/ga/Documents/SlicerData/Models/brain_highres.vtk"
GT_FILE="/var/lib/slicer/ground_truth/decimate_task_gt.json"
RESULT_FILE="/tmp/decimate_result.json"

# Initialize result values
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
TIMESTAMP_VALID="false"
SLICER_RUNNING="false"

# Check if Slicer is running
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Check output file
if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    
    # Check timestamp validity
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        TIMESTAMP_VALID="true"
        echo "Output file created during task: $EXPECTED_OUTPUT"
    else
        echo "WARNING: Output file predates task start"
    fi
    echo "Output file size: $OUTPUT_SIZE bytes"
else
    echo "Output file not found at: $EXPECTED_OUTPUT"
    
    # Search for alternative output locations
    echo "Searching for VTK files..."
    find /home/ga -name "*.vtk" -newer /tmp/task_start_time.txt 2>/dev/null | head -5
fi

# Analyze model files using Python/VTK
python3 << PYEOF
import json
import os
import sys

result = {
    "output_exists": $( [ "$OUTPUT_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_running": $( [ "$SLICER_RUNNING" = "true" ] && echo "true" || echo "false" ),
    "timestamp_valid": $( [ "$TIMESTAMP_VALID" = "true" ] && echo "true" || echo "false" ),
    "output_polygons": 0,
    "output_vertices": 0,
    "original_polygons": 0,
    "original_vertices": 0,
    "original_file_size": 0,
    "reduction_percent": 0,
    "model_valid": False,
    "has_geometry": False,
    "bounding_box": []
}

# Try to import VTK
try:
    import vtk
    HAS_VTK = True
except ImportError:
    print("VTK not available, limited verification", file=sys.stderr)
    HAS_VTK = False

# Load ground truth
gt_path = "$GT_FILE"
if os.path.exists(gt_path):
    try:
        with open(gt_path, 'r') as f:
            gt = json.load(f)
            result["original_polygons"] = gt.get("original_polygons", 0)
            result["original_vertices"] = gt.get("original_vertices", 0)
            result["original_file_size"] = gt.get("original_file_size_bytes", 0)
            print(f"Ground truth: {result['original_polygons']} original polygons")
    except Exception as e:
        print(f"Error loading ground truth: {e}", file=sys.stderr)

# Analyze original model if ground truth not available
original_path = "$ORIGINAL_MODEL"
if result["original_polygons"] == 0 and HAS_VTK and os.path.exists(original_path):
    try:
        reader = vtk.vtkPolyDataReader()
        reader.SetFileName(original_path)
        reader.Update()
        polydata = reader.GetOutput()
        if polydata:
            result["original_polygons"] = polydata.GetNumberOfPolys()
            result["original_vertices"] = polydata.GetNumberOfPoints()
            result["original_file_size"] = os.path.getsize(original_path)
            print(f"Original model: {result['original_polygons']} polygons")
    except Exception as e:
        print(f"Error reading original model: {e}", file=sys.stderr)

# Analyze output file if it exists
output_path = "$EXPECTED_OUTPUT"
if os.path.exists(output_path) and HAS_VTK:
    try:
        reader = vtk.vtkPolyDataReader()
        reader.SetFileName(output_path)
        reader.Update()
        polydata = reader.GetOutput()
        
        if polydata:
            num_polys = polydata.GetNumberOfPolys()
            num_points = polydata.GetNumberOfPoints()
            
            result["output_polygons"] = num_polys
            result["output_vertices"] = num_points
            result["has_geometry"] = num_polys > 0 and num_points > 0
            
            print(f"Output model: {num_polys} polygons, {num_points} vertices")
            
            # Check if model is valid (has reasonable geometry)
            if num_polys > 100:
                bounds = polydata.GetBounds()
                extent = [bounds[1]-bounds[0], bounds[3]-bounds[2], bounds[5]-bounds[4]]
                result["model_valid"] = all(e > 0 for e in extent)
                result["bounding_box"] = list(bounds)
                print(f"Bounding box: {bounds}")
            
            # Calculate reduction percentage
            if result["original_polygons"] > 0:
                reduction = (1 - num_polys / result["original_polygons"]) * 100
                result["reduction_percent"] = round(reduction, 2)
                print(f"Polygon reduction: {reduction:.2f}%")
                
    except Exception as e:
        print(f"Error reading output model: {e}", file=sys.stderr)
        result["error"] = str(e)

elif os.path.exists(output_path):
    # VTK not available, just check file size as proxy
    result["output_size_bytes"] = os.path.getsize(output_path)
    if result["original_file_size"] > 0:
        size_reduction = (1 - result["output_size_bytes"] / result["original_file_size"]) * 100
        result["file_size_reduction_percent"] = round(size_reduction, 2)
        print(f"File size reduction: {size_reduction:.2f}%")

# Save result
result_path = "$RESULT_FILE"
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"\nResult saved to: {result_path}")
print(json.dumps(result, indent=2))
PYEOF

# Copy final screenshot to accessible location
if [ -f /tmp/task_final_state.png ]; then
    mkdir -p /home/ga/Documents/SlicerData/Screenshots 2>/dev/null || true
    cp /tmp/task_final_state.png /home/ga/Documents/SlicerData/Screenshots/decimate_final.png 2>/dev/null || true
fi

# Ensure result file is readable
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
cat "$RESULT_FILE" 2>/dev/null || echo "Could not read result file"