#!/bin/bash
echo "=== Exporting Curved Path Measurement Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_CURVE="$AMOS_DIR/aorta_curve.mrk.json"
RESULT_FILE="/tmp/curve_task_result.json"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION}s"

# Take final screenshot
mkdir -p "$SCREENSHOT_DIR"
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
cp /tmp/task_final.png "$SCREENSHOT_DIR/curve_task_final.png" 2>/dev/null || true
echo "Final screenshot captured"

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Create Python script to extract curve data from Slicer
EXTRACT_SCRIPT="/tmp/extract_curve_data.py"
cat > "$EXTRACT_SCRIPT" << 'PYEOF'
import slicer
import json
import os
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
result_path = "/tmp/curve_task_result.json"

result = {
    "slicer_running": True,
    "curve_exists": False,
    "curve_count": 0,
    "curve_name": "",
    "num_control_points": 0,
    "curve_length_mm": 0.0,
    "points_positions": [],
    "z_span_mm": 0.0,
    "xy_drift_mm": 0.0,
    "length_in_range": False,
    "spatial_valid": False,
    "data_loaded": False,
    "curve_file_saved": False,
    "screenshot_final": "/tmp/task_final.png"
}

try:
    # Check if volume is loaded
    volumeNodes = slicer.mrmlScene.GetNodesByClass("vtkMRMLScalarVolumeNode")
    result["data_loaded"] = volumeNodes.GetNumberOfItems() > 0
    if result["data_loaded"]:
        print(f"Volume loaded: {volumeNodes.GetItemAsObject(0).GetName()}")
    
    # Get curve markups
    curveNodes = slicer.mrmlScene.GetNodesByClass("vtkMRMLMarkupsCurveNode")
    result["curve_count"] = curveNodes.GetNumberOfItems()
    result["curve_exists"] = result["curve_count"] > 0
    
    print(f"Found {result['curve_count']} curve markup(s)")
    
    if result["curve_exists"]:
        # Get the first (or most significant) curve
        best_curve = None
        best_length = 0
        
        for i in range(curveNodes.GetNumberOfItems()):
            curve = curveNodes.GetItemAsObject(i)
            if curve and curve.GetNumberOfControlPoints() > 0:
                length = curve.GetCurveLengthWorld()
                if length > best_length:
                    best_length = length
                    best_curve = curve
        
        if best_curve:
            curve = best_curve
            result["curve_name"] = curve.GetName()
            result["num_control_points"] = curve.GetNumberOfControlPoints()
            
            # Get curve length
            result["curve_length_mm"] = curve.GetCurveLengthWorld()
            
            print(f"Curve '{result['curve_name']}': {result['num_control_points']} points, {result['curve_length_mm']:.2f} mm")
            
            # Check if length is in expected anatomical range
            result["length_in_range"] = 80.0 <= result["curve_length_mm"] <= 160.0
            
            # Extract control point positions for spatial validation
            points = []
            for i in range(curve.GetNumberOfControlPoints()):
                pos = [0.0, 0.0, 0.0]
                curve.GetNthControlPointPosition(i, pos)
                points.append(pos)
            result["points_positions"] = points
            
            if len(points) >= 2:
                # Calculate Z-span (should cover significant distance for aorta)
                z_vals = [p[2] for p in points]
                result["z_span_mm"] = abs(max(z_vals) - min(z_vals))
                
                # Calculate XY drift (aorta is roughly vertical, so XY shouldn't vary much)
                x_vals = [p[0] for p in points]
                y_vals = [p[1] for p in points]
                x_range = max(x_vals) - min(x_vals)
                y_range = max(y_vals) - min(y_vals)
                result["xy_drift_mm"] = max(x_range, y_range)
                
                # Spatial validity: significant Z span, limited XY drift
                result["spatial_valid"] = (result["z_span_mm"] > 50.0 and 
                                           result["xy_drift_mm"] < 50.0)
                
                print(f"Z-span: {result['z_span_mm']:.1f} mm, XY-drift: {result['xy_drift_mm']:.1f} mm")
            
            # Try to save the curve
            output_path = os.path.join(output_dir, "aorta_curve.mrk.json")
            try:
                success = slicer.util.saveNode(curve, output_path)
                result["curve_file_saved"] = success
                if success:
                    print(f"Curve saved to {output_path}")
                else:
                    print("Failed to save curve")
            except Exception as e:
                print(f"Error saving curve: {e}")
    
except Exception as e:
    result["error"] = str(e)
    print(f"Error: {e}")

# Write result
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Results written to {result_path}")
PYEOF

# Execute extraction script if Slicer is running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting curve data from Slicer..."
    
    # Run the extraction script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script "$EXTRACT_SCRIPT" > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    
    # Wait with timeout
    for i in $(seq 1 20); do
        if [ -f "$RESULT_FILE" ]; then
            echo "Extraction complete after ${i}s"
            break
        fi
        sleep 1
    done
    
    # Kill extraction process if still running
    kill $EXTRACT_PID 2>/dev/null || true
fi

# If result file doesn't exist, create minimal result
if [ ! -f "$RESULT_FILE" ]; then
    echo "Creating minimal result (extraction may have failed)"
    
    # Check for manually saved curve file
    CURVE_FILE_EXISTS="false"
    if [ -f "$OUTPUT_CURVE" ]; then
        CURVE_FILE_EXISTS="true"
    fi
    
    # Also check for any .mrk.json files created during task
    NEW_CURVE_FILES=$(find "$AMOS_DIR" -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l || echo "0")
    
    cat > "$RESULT_FILE" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "curve_exists": $CURVE_FILE_EXISTS,
    "curve_count": 0,
    "curve_file_saved": $CURVE_FILE_EXISTS,
    "new_curve_files": $NEW_CURVE_FILES,
    "extraction_failed": true,
    "error": "Could not extract curve data from Slicer"
}
EOF
fi

# Add task timing info to result
python3 << PYEOF
import json
import os

result_file = "$RESULT_FILE"
task_start = $TASK_START
task_end = $TASK_END
task_duration = $TASK_DURATION

try:
    with open(result_file, "r") as f:
        data = json.load(f)
except:
    data = {}

data["task_start_time"] = task_start
data["task_end_time"] = task_end
data["task_duration_seconds"] = task_duration

with open(result_file, "w") as f:
    json.dump(data, f, indent=2)

print("Timing info added to result")
PYEOF

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
echo "Result file: $RESULT_FILE"
cat "$RESULT_FILE"