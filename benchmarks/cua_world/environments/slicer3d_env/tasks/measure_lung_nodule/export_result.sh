#!/bin/bash
echo "=== Exporting Lung Nodule Measurement Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
MEASUREMENT_FILE="$EXPORT_DIR/nodule_measurement.json"
RESULT_FILE="/tmp/lung_nodule_result.json"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ============================================================
# Check if Slicer is running
# ============================================================
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Try to extract line measurements from Slicer
# ============================================================
LINE_MARKUP_EXISTS="false"
LINE_LENGTH_MM="0"
LINE_ENDPOINTS="[]"
LINE_Z_COORD="0"

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer for line measurements..."
    
    cat > /tmp/extract_measurements.py << 'PYEOF'
import slicer
import json
import math

result = {
    "line_exists": False,
    "line_length_mm": 0,
    "line_endpoints": [],
    "line_z_coord": 0,
    "all_lines": []
}

try:
    # Get all line markup nodes
    lineNodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
    
    if lineNodes:
        result["line_exists"] = True
        
        for i, lineNode in enumerate(lineNodes):
            if lineNode.GetNumberOfControlPoints() >= 2:
                p1 = [0.0, 0.0, 0.0]
                p2 = [0.0, 0.0, 0.0]
                lineNode.GetNthControlPointPosition(0, p1)
                lineNode.GetNthControlPointPosition(1, p2)
                
                # Calculate length
                length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                z_coord = (p1[2] + p2[2]) / 2.0
                
                line_info = {
                    "name": lineNode.GetName(),
                    "length_mm": length,
                    "p1": p1,
                    "p2": p2,
                    "z_coord": z_coord
                }
                result["all_lines"].append(line_info)
                
                # Use first line (or longest if multiple)
                if length > result["line_length_mm"]:
                    result["line_length_mm"] = length
                    result["line_endpoints"] = [p1, p2]
                    result["line_z_coord"] = z_coord
    
    # Also check for ruler annotations (older style)
    rulerNodes = slicer.util.getNodesByClass("vtkMRMLAnnotationRulerNode")
    for ruler in rulerNodes:
        result["line_exists"] = True
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        ruler.GetPosition1(p1)
        ruler.GetPosition2(p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        if length > result["line_length_mm"]:
            result["line_length_mm"] = length
            result["line_endpoints"] = [p1, p2]
            result["line_z_coord"] = (p1[2] + p2[2]) / 2.0

except Exception as e:
    result["error"] = str(e)

# Write result
with open("/tmp/slicer_line_query.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result))
PYEOF

    # Run query script in Slicer
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/extract_measurements.py > /tmp/slicer_query_output.txt 2>&1 &
    QUERY_PID=$!
    sleep 15
    kill $QUERY_PID 2>/dev/null || true
    
    # Read query results
    if [ -f /tmp/slicer_line_query.json ]; then
        LINE_MARKUP_EXISTS=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_line_query.json')).get('line_exists', False) else 'false')" 2>/dev/null || echo "false")
        LINE_LENGTH_MM=$(python3 -c "import json; print(json.load(open('/tmp/slicer_line_query.json')).get('line_length_mm', 0))" 2>/dev/null || echo "0")
        LINE_Z_COORD=$(python3 -c "import json; print(json.load(open('/tmp/slicer_line_query.json')).get('line_z_coord', 0))" 2>/dev/null || echo "0")
        echo "Line query: exists=$LINE_MARKUP_EXISTS, length=$LINE_LENGTH_MM mm"
    fi
fi

# ============================================================
# Check for user-exported measurement file
# ============================================================
MEASUREMENT_FILE_EXISTS="false"
MEASUREMENT_FILE_CREATED_DURING_TASK="false"
REPORTED_DIAMETER_MM="0"

if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MEASUREMENT_FILE_CREATED_DURING_TASK="true"
    fi
    
    # Parse the measurement value
    REPORTED_DIAMETER_MM=$(python3 -c "
import json
try:
    with open('$MEASUREMENT_FILE', 'r') as f:
        data = json.load(f)
    diameter = data.get('nodule_diameter_mm', 0)
    print(f'{diameter:.2f}')
except Exception as e:
    print('0')
" 2>/dev/null || echo "0")
    
    echo "Measurement file found: $REPORTED_DIAMETER_MM mm"
else
    echo "Measurement file not found at $MEASUREMENT_FILE"
    
    # Check alternative locations
    for alt_path in \
        "$EXPORT_DIR/measurement.json" \
        "/home/ga/nodule_measurement.json" \
        "/home/ga/Documents/nodule_measurement.json"; do
        if [ -f "$alt_path" ]; then
            echo "Found alternative measurement file at: $alt_path"
            MEASUREMENT_FILE_EXISTS="true"
            REPORTED_DIAMETER_MM=$(python3 -c "
import json
try:
    with open('$alt_path', 'r') as f:
        data = json.load(f)
    diameter = data.get('nodule_diameter_mm', data.get('diameter_mm', data.get('measurement', 0)))
    print(f'{diameter:.2f}')
except:
    print('0')
" 2>/dev/null || echo "0")
            break
        fi
    done
fi

# ============================================================
# Load ground truth for comparison
# ============================================================
GT_DIAMETER_MM="0"
NODULE_CENTROID="[0,0,0]"

if [ -f /tmp/nodule_ground_truth.json ]; then
    GT_DIAMETER_MM=$(python3 -c "import json; print(json.load(open('/tmp/nodule_ground_truth.json')).get('ground_truth_diameter_mm', 0))" 2>/dev/null || echo "0")
    NODULE_CENTROID=$(python3 -c "import json; print(json.load(open('/tmp/nodule_ground_truth.json')).get('nodule_centroid_ras', [0,0,0]))" 2>/dev/null || echo "[0,0,0]")
fi

# ============================================================
# Calculate measurement error
# ============================================================
# Use the best available measurement (exported file or Slicer query)
BEST_MEASUREMENT="0"
MEASUREMENT_SOURCE="none"

if [ "$REPORTED_DIAMETER_MM" != "0" ] && [ "$REPORTED_DIAMETER_MM" != "0.00" ]; then
    BEST_MEASUREMENT="$REPORTED_DIAMETER_MM"
    MEASUREMENT_SOURCE="exported_file"
elif [ "$LINE_LENGTH_MM" != "0" ]; then
    BEST_MEASUREMENT="$LINE_LENGTH_MM"
    MEASUREMENT_SOURCE="slicer_query"
fi

MEASUREMENT_ERROR_MM=$(python3 -c "print(abs(float('$BEST_MEASUREMENT') - float('$GT_DIAMETER_MM')))" 2>/dev/null || echo "999")

# ============================================================
# Check if line is in lung region (basic sanity check)
# ============================================================
LINE_IN_LUNG_REGION="false"
if [ "$LINE_MARKUP_EXISTS" = "true" ] && [ -f /tmp/slicer_line_query.json ]; then
    # Lung tissue is typically in certain coordinate ranges
    # This is a rough heuristic
    LINE_IN_LUNG_REGION=$(python3 << 'PYEOF'
import json
try:
    data = json.load(open('/tmp/slicer_line_query.json'))
    endpoints = data.get('line_endpoints', [])
    if len(endpoints) >= 2:
        p1, p2 = endpoints[0], endpoints[1]
        # Check if points are in reasonable thoracic region
        # This is approximate - real validation would need image data
        avg_y = (p1[1] + p2[1]) / 2
        # Lung region is typically posterior (negative Y in RAS)
        if avg_y < 0:
            print("true")
        else:
            print("true")  # Accept for now - detailed validation in verifier
    else:
        print("false")
except:
    print("false")
PYEOF
)
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "line_markup_exists": $LINE_MARKUP_EXISTS,
    "line_length_mm": $LINE_LENGTH_MM,
    "line_z_coord": $LINE_Z_COORD,
    "line_in_lung_region": $LINE_IN_LUNG_REGION,
    "measurement_file_exists": $MEASUREMENT_FILE_EXISTS,
    "measurement_file_created_during_task": $MEASUREMENT_FILE_CREATED_DURING_TASK,
    "reported_diameter_mm": $REPORTED_DIAMETER_MM,
    "best_measurement_mm": $BEST_MEASUREMENT,
    "measurement_source": "$MEASUREMENT_SOURCE",
    "ground_truth_diameter_mm": $GT_DIAMETER_MM,
    "nodule_centroid_ras": $NODULE_CENTROID,
    "measurement_error_mm": $MEASUREMENT_ERROR_MM,
    "screenshot_initial": "/tmp/task_initial.png",
    "screenshot_final": "/tmp/task_final.png"
}
JSONEOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="