#!/bin/bash
echo "=== Exporting Cerebellar Vermis Assessment Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$BRATS_DIR/vermis_measurement.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/vermis_report.json"

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/vermis_final_screenshot.png 2>/dev/null || true
sleep 1

# Check if Slicer is/was running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Try to export measurements from Slicer if running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to export measurements from Slicer..."
    
    cat > /tmp/export_vermis_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

measurements = []

# Check for line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        measurements.append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "point1": p1,
            "point2": p2,
        })
        print(f"  Line '{node.GetName()}': {length:.1f} mm")
        
        # Save the markup node directly
        mrk_path = os.path.join(output_dir, "vermis_measurement.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved markup to {mrk_path}")

# Also check for fiducials
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        measurements.append({
            "name": node.GetNthControlPointLabel(i),
            "type": "fiducial",
            "position": pos,
        })

if measurements:
    meas_path = os.path.join(output_dir, "slicer_measurements.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Exported measurements to {meas_path}")

print("Export script complete")
PYEOF

    # Run export script briefly
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_vermis_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_VALID="false"
MEASURED_DISTANCE=""
POINT1=""
POINT2=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$BRATS_DIR/vermis_measurement.mrk.json"
    "$BRATS_DIR/measurement.mrk.json"
    "/home/ga/Documents/vermis_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        echo "Found measurement at: $path"
        
        # Validate JSON and extract data
        MEAS_DATA=$(python3 << PYEOF
import json
import math

try:
    with open('$path', 'r') as f:
        data = json.load(f)
    
    result = {"valid": True, "distance": None, "point1": None, "point2": None}
    
    # Slicer markup JSON structure
    markups = data.get('markups', [])
    if markups:
        markup = markups[0]
        control_points = markup.get('controlPoints', [])
        if len(control_points) >= 2:
            p1 = control_points[0].get('position', [0,0,0])
            p2 = control_points[1].get('position', [0,0,0])
            dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1,p2)))
            result['distance'] = round(dist, 2)
            result['point1'] = p1
            result['point2'] = p2
    
    # Also check alternative structure
    if result['distance'] is None:
        measurements = data.get('measurements', [])
        for m in measurements:
            if m.get('type') == 'line' and m.get('length_mm'):
                result['distance'] = round(m['length_mm'], 2)
                result['point1'] = m.get('point1', m.get('p1', []))
                result['point2'] = m.get('point2', m.get('p2', []))
                break
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
        
        MEASUREMENT_VALID=$(echo "$MEAS_DATA" | python3 -c "import sys,json; print('true' if json.load(sys.stdin).get('valid') else 'false')" 2>/dev/null || echo "false")
        MEASURED_DISTANCE=$(echo "$MEAS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin).get('distance'); print(d if d else '')" 2>/dev/null || echo "")
        POINT1=$(echo "$MEAS_DATA" | python3 -c "import sys,json; p=json.load(sys.stdin).get('point1'); print(p if p else '[]')" 2>/dev/null || echo "[]")
        POINT2=$(echo "$MEAS_DATA" | python3 -c "import sys,json; p=json.load(sys.stdin).get('point2'); print(p if p else '[]')" 2>/dev/null || echo "[]")
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

echo "Measurement exists: $MEASUREMENT_EXISTS"
echo "Measurement valid: $MEASUREMENT_VALID"
echo "Measured distance: $MEASURED_DISTANCE mm"

# Check for report file
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_HAS_AP="false"
REPORT_HAS_MORPHOLOGY="false"
REPORTED_AP=""
REPORTED_CLASSIFICATION=""
REPORTED_MORPHOLOGY=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/vermis_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/vermis_report.json"
    "/home/ga/vermis_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Parse report
        REPORT_DATA=$(python3 << PYEOF
import json
try:
    with open('$path', 'r') as f:
        data = json.load(f)
    
    result = {"valid": True}
    
    # Look for AP diameter in various field names
    ap_fields = ['ap_diameter', 'ap_diameter_mm', 'anteroposterior_diameter', 
                 'ap', 'diameter', 'vermis_ap', 'vermis_diameter', 'measurement']
    for field in ap_fields:
        if field in data:
            result['ap_diameter'] = data[field]
            break
        for key in data:
            if isinstance(data[key], dict) and field in data[key]:
                result['ap_diameter'] = data[key][field]
                break
    
    # Look for morphology
    morph_fields = ['morphology', 'assessment', 'finding', 'description']
    for field in morph_fields:
        if field in data:
            result['morphology'] = str(data[field])
            break
    
    # Look for classification
    class_fields = ['classification', 'clinical_classification', 'status', 'category']
    for field in class_fields:
        if field in data:
            result['classification'] = str(data[field])
            break
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
        
        REPORT_VALID=$(echo "$REPORT_DATA" | python3 -c "import sys,json; print('true' if json.load(sys.stdin).get('valid') else 'false')" 2>/dev/null || echo "false")
        REPORTED_AP=$(echo "$REPORT_DATA" | python3 -c "import sys,json; v=json.load(sys.stdin).get('ap_diameter'); print(v if v is not None else '')" 2>/dev/null || echo "")
        REPORTED_MORPHOLOGY=$(echo "$REPORT_DATA" | python3 -c "import sys,json; v=json.load(sys.stdin).get('morphology',''); print(v)" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(echo "$REPORT_DATA" | python3 -c "import sys,json; v=json.load(sys.stdin).get('classification',''); print(v)" 2>/dev/null || echo "")
        
        [ -n "$REPORTED_AP" ] && REPORT_HAS_AP="true"
        [ -n "$REPORTED_MORPHOLOGY" ] && REPORT_HAS_MORPHOLOGY="true"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

echo "Report exists: $REPORT_EXISTS"
echo "Report valid: $REPORT_VALID"
echo "Reported AP: $REPORTED_AP"
echo "Reported classification: $REPORTED_CLASSIFICATION"

# Get task timing
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Check if files were created during task (anti-gaming)
MEAS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$START_TIME" ]; then
        MEAS_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$START_TIME" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_vermis_gt.json" /tmp/vermis_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/vermis_ground_truth.json 2>/dev/null || true

# Build result JSON
TEMP_JSON=$(mktemp /tmp/vermis_result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_id": "cerebellar_vermis_assessment",
    "sample_id": "$SAMPLE_ID",
    "slicer_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_file_valid": $MEASUREMENT_VALID,
    "measurement_created_during_task": $MEAS_CREATED_DURING_TASK,
    "measured_distance_mm": "$MEASURED_DISTANCE",
    "measurement_point1": "$POINT1",
    "measurement_point2": "$POINT2",
    "report_file_exists": $REPORT_EXISTS,
    "report_file_valid": $REPORT_VALID,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_has_ap_diameter": $REPORT_HAS_AP,
    "report_has_morphology": $REPORT_HAS_MORPHOLOGY,
    "reported_ap_diameter": "$REPORTED_AP",
    "reported_morphology": "$REPORTED_MORPHOLOGY",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "task_start_time": $START_TIME,
    "task_end_time": $END_TIME,
    "elapsed_seconds": $ELAPSED,
    "screenshot_path": "/tmp/vermis_final_screenshot.png"
}
JSONEOF

# Move to final location
rm -f /tmp/vermis_task_result.json 2>/dev/null || sudo rm -f /tmp/vermis_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/vermis_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/vermis_task_result.json
chmod 666 /tmp/vermis_task_result.json 2>/dev/null || sudo chmod 666 /tmp/vermis_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result exported to /tmp/vermis_task_result.json"
cat /tmp/vermis_task_result.json
echo ""
echo "=== Export Complete ==="