#!/bin/bash
echo "=== Exporting Tumor Diameter Measurement Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record export time
EXPORT_TIME=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start time: $TASK_START"
echo "Export time: $EXPORT_TIME"

# Take final screenshot first
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Get sample ID
SAMPLE_ID=$(cat /tmp/brats_sample_id 2>/dev/null || echo "BraTS2021_00000")
SCREENSHOT_PATH="/home/ga/Documents/SlicerData/Screenshots/tumor_measurement.png"

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
fi

# Check for saved screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
SCREENSHOT_MTIME=0

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c%s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c%Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    echo "User screenshot found: $SCREENSHOT_PATH ($SCREENSHOT_SIZE bytes)"
    # Copy for verification
    cp "$SCREENSHOT_PATH" /tmp/user_tumor_screenshot.png 2>/dev/null || true
fi

# Check if screenshot was created during task
SCREENSHOT_CREATED_DURING_TASK="false"
if [ "$SCREENSHOT_EXISTS" = "true" ] && [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
    SCREENSHOT_CREATED_DURING_TASK="true"
    echo "Screenshot was created during task"
fi

# Extract measurement from Slicer using Python API
echo "Extracting measurements from Slicer..."

MARKUP_EXISTS="false"
MEASUREMENT_MM="0"
NUM_LINE_NODES=0
LINE_ENDPOINTS=""

if [ "$SLICER_RUNNING" = "true" ]; then
    # Create extraction script
    cat > /tmp/extract_tumor_measurement.py << 'PYEOF'
import json
import math
import os

result = {
    "markup_exists": False,
    "measurement_mm": 0,
    "num_line_nodes": 0,
    "line_endpoints": [],
    "markup_name": "",
    "all_measurements": []
}

try:
    import slicer
    
    # Find line markups (ruler measurements)
    line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
    result["num_line_nodes"] = len(line_nodes)
    
    if line_nodes:
        result["markup_exists"] = True
        
        for node in line_nodes:
            if node.GetNumberOfControlPoints() >= 2:
                p0 = [0.0, 0.0, 0.0]
                p1 = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(0, p0)
                node.GetNthControlPointPosition(1, p1)
                
                length = math.sqrt(sum((a-b)**2 for a, b in zip(p0, p1)))
                
                measurement = {
                    "name": node.GetName(),
                    "length_mm": round(length, 2),
                    "p0": [round(x, 2) for x in p0],
                    "p1": [round(x, 2) for x in p1],
                    "z_coord": round((p0[2] + p1[2]) / 2, 2)
                }
                result["all_measurements"].append(measurement)
                
                # Use first valid measurement
                if result["measurement_mm"] == 0 and length > 0:
                    result["measurement_mm"] = round(length, 2)
                    result["markup_name"] = node.GetName()
                    result["line_endpoints"] = [[round(x, 2) for x in p0], [round(x, 2) for x in p1]]
                
                print(f"Found line '{node.GetName()}': {length:.2f} mm")
    
    # Also check for any ruler annotations
    ruler_nodes = slicer.util.getNodesByClass("vtkMRMLAnnotationRulerNode")
    for node in ruler_nodes:
        p0 = [0.0, 0.0, 0.0]
        p1 = [0.0, 0.0, 0.0]
        node.GetPosition1(p0)
        node.GetPosition2(p1)
        length = math.sqrt(sum((a-b)**2 for a, b in zip(p0, p1)))
        if length > 0:
            result["markup_exists"] = True
            if result["measurement_mm"] == 0:
                result["measurement_mm"] = round(length, 2)
            result["all_measurements"].append({
                "name": node.GetName(),
                "length_mm": round(length, 2),
                "type": "ruler_annotation"
            })
            print(f"Found ruler annotation '{node.GetName()}': {length:.2f} mm")

except Exception as e:
    result["error"] = str(e)
    print(f"Error: {e}")

# Save result
output_path = "/tmp/slicer_measurement_extract.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Extraction complete. Result saved to {output_path}")
PYEOF

    # Run extraction script in Slicer's Python environment
    # Use --no-main-window to run headless but still access the scene
    chmod 644 /tmp/extract_tumor_measurement.py
    
    # Try to execute via Slicer's Python
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_tumor_measurement.py --no-splash > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    sleep 15
    kill $EXTRACT_PID 2>/dev/null || true
    
    # Read extraction results
    if [ -f /tmp/slicer_measurement_extract.json ]; then
        echo "Measurement extraction succeeded"
        cat /tmp/slicer_measurement_extract.json
        
        MARKUP_EXISTS=$(python3 -c "import json; d=json.load(open('/tmp/slicer_measurement_extract.json')); print(str(d.get('markup_exists', False)).lower())" 2>/dev/null || echo "false")
        MEASUREMENT_MM=$(python3 -c "import json; d=json.load(open('/tmp/slicer_measurement_extract.json')); print(d.get('measurement_mm', 0))" 2>/dev/null || echo "0")
        NUM_LINE_NODES=$(python3 -c "import json; d=json.load(open('/tmp/slicer_measurement_extract.json')); print(d.get('num_line_nodes', 0))" 2>/dev/null || echo "0")
    else
        echo "Measurement extraction did not produce output"
    fi
fi

# Load ground truth
GT_PATH="/tmp/tumor_diameter_gt.json"
GT_DIAMETER="0"
GT_MIN="0"
GT_MAX="0"
GT_AVAILABLE="false"

if [ -f "$GT_PATH" ]; then
    GT_DIAMETER=$(python3 -c "import json; d=json.load(open('$GT_PATH')); print(d.get('max_diameter_mm', 0))" 2>/dev/null || echo "0")
    GT_MIN=$(python3 -c "import json; d=json.load(open('$GT_PATH')); print(d.get('min_acceptable_mm', 0))" 2>/dev/null || echo "0")
    GT_MAX=$(python3 -c "import json; d=json.load(open('$GT_PATH')); print(d.get('max_acceptable_mm', 0))" 2>/dev/null || echo "0")
    GT_AVAILABLE=$(python3 -c "import json; d=json.load(open('$GT_PATH')); print(str(d.get('gt_available', False)).lower())" 2>/dev/null || echo "false")
    echo "Ground truth: ${GT_DIAMETER} mm (range: ${GT_MIN} - ${GT_MAX} mm)"
fi

# Create final result JSON
RESULT_FILE="/tmp/tumor_measurement_result.json"

cat > "$RESULT_FILE" << RESULTEOF
{
    "sample_id": "$SAMPLE_ID",
    "task_start_time": $TASK_START,
    "export_time": $EXPORT_TIME,
    "slicer_running": $SLICER_RUNNING,
    "markup_exists": $MARKUP_EXISTS,
    "measurement_mm": $MEASUREMENT_MM,
    "num_line_nodes": $NUM_LINE_NODES,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "ground_truth_diameter_mm": $GT_DIAMETER,
    "acceptable_min_mm": $GT_MIN,
    "acceptable_max_mm": $GT_MAX,
    "ground_truth_available": $GT_AVAILABLE
}
RESULTEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Export Results ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="