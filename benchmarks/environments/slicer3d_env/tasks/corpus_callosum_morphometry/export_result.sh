#!/bin/bash
echo "=== Exporting Corpus Callosum Morphometry Result ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$SAMPLE_DIR/cc_measurements.mrk.json"
OUTPUT_REPORT="$SAMPLE_DIR/corpus_callosum_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/cc_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_cc_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/SampleData"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

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
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": round(length, 2),
            "point1_ras": [round(x, 2) for x in p1],
            "point2_ras": [round(x, 2) for x in p2],
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Save individual markup
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, mrk_path)

# Check for fiducial markups
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        all_measurements.append({
            "name": node.GetNthControlPointLabel(i),
            "type": "fiducial",
            "position_ras": [round(x, 2) for x in pos],
        })

# Save combined measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "cc_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No measurements found in scene")

# Get current slice offsets for verification
try:
    green_slice = slicer.app.layoutManager().sliceWidget("Green").sliceLogic().GetSliceNode()
    sagittal_offset = green_slice.GetSliceOffset()
    print(f"Current sagittal slice offset: {sagittal_offset}")
    
    # Save slice info
    slice_info = {"sagittal_offset": sagittal_offset}
    with open("/tmp/cc_slice_info.json", "w") as f:
        json.dump(slice_info, f)
except Exception as e:
    print(f"Could not get slice info: {e}")

print("Export complete")
PYEOF

    # Run export script
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_cc_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_COUNT=0
MEASUREMENTS_JSON="{}"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$SAMPLE_DIR/cc_measurements.mrk.json"
    "$SAMPLE_DIR/measurements.mrk.json"
    "/home/ga/Documents/cc_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        echo "Found measurements at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        MEASUREMENTS_JSON=$(cat "$path" 2>/dev/null || echo "{}")
        MEASUREMENT_COUNT=$(python3 -c "import json; d=json.loads('$MEASUREMENTS_JSON'); print(len(d.get('measurements', [])))" 2>/dev/null || echo "0")
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_JSON="{}"
REPORTED_LENGTH=""
REPORTED_GENU=""
REPORTED_BODY=""
REPORTED_SPLENIUM=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$SAMPLE_DIR/corpus_callosum_report.json"
    "$SAMPLE_DIR/cc_report.json"
    "$SAMPLE_DIR/report.json"
    "/home/ga/Documents/corpus_callosum_report.json"
    "/home/ga/corpus_callosum_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        REPORT_JSON=$(cat "$path" 2>/dev/null || echo "{}")
        
        # Extract values from report
        REPORTED_LENGTH=$(python3 -c "
import json
d = json.loads('''$REPORT_JSON''')
# Try various key formats
for key in ['total_length_mm', 'length_mm', 'total_length', 'length']:
    if key in d:
        print(d[key])
        break
    if 'measurements' in d and key in d['measurements']:
        print(d['measurements'][key])
        break
" 2>/dev/null || echo "")
        
        REPORTED_GENU=$(python3 -c "
import json
d = json.loads('''$REPORT_JSON''')
for key in ['genu_thickness_mm', 'genu_mm', 'genu_thickness', 'genu']:
    if key in d:
        print(d[key])
        break
    if 'measurements' in d and key in d['measurements']:
        print(d['measurements'][key])
        break
" 2>/dev/null || echo "")
        
        REPORTED_BODY=$(python3 -c "
import json
d = json.loads('''$REPORT_JSON''')
for key in ['body_thickness_mm', 'body_mm', 'body_thickness', 'body']:
    if key in d:
        print(d[key])
        break
    if 'measurements' in d and key in d['measurements']:
        print(d['measurements'][key])
        break
" 2>/dev/null || echo "")
        
        REPORTED_SPLENIUM=$(python3 -c "
import json
d = json.loads('''$REPORT_JSON''')
for key in ['splenium_thickness_mm', 'splenium_mm', 'splenium_thickness', 'splenium']:
    if key in d:
        print(d[key])
        break
    if 'measurements' in d and key in d['measurements']:
        print(d['measurements'][key])
        break
" 2>/dev/null || echo "")
        
        REPORTED_CLASSIFICATION=$(python3 -c "
import json
d = json.loads('''$REPORT_JSON''')
for key in ['atrophy_grade', 'classification', 'assessment', 'atrophy']:
    if key in d:
        print(d[key])
        break
    if 'clinical_assessment' in d and key in d['clinical_assessment']:
        print(d['clinical_assessment'][key])
        break
" 2>/dev/null || echo "")
        
        echo "Extracted from report:"
        echo "  Length: $REPORTED_LENGTH mm"
        echo "  Genu: $REPORTED_GENU mm"
        echo "  Body: $REPORTED_BODY mm"
        echo "  Splenium: $REPORTED_SPLENIUM mm"
        echo "  Classification: $REPORTED_CLASSIFICATION"
        break
    fi
done

# Try to extract measurements from markup file if not in report
if [ -z "$REPORTED_LENGTH" ] && [ "$MEASUREMENT_EXISTS" = "true" ]; then
    echo "Attempting to extract measurements from markup file..."
    python3 << 'PYEOF'
import json
import os

meas_file = "/home/ga/Documents/SlicerData/SampleData/cc_measurements.mrk.json"
if os.path.exists(meas_file):
    with open(meas_file) as f:
        data = json.load(f)
    
    measurements = data.get('measurements', [])
    for m in measurements:
        if m.get('type') == 'line':
            name = m.get('name', '').lower()
            length = m.get('length_mm', 0)
            print(f"Found: {name} = {length} mm")
PYEOF
fi

# Get slice info if available
SAGITTAL_SLICE=""
if [ -f /tmp/cc_slice_info.json ]; then
    SAGITTAL_SLICE=$(python3 -c "import json; print(json.load(open('/tmp/cc_slice_info.json')).get('sagittal_offset', ''))" 2>/dev/null || echo "")
fi

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

REPORT_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_REPORT" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/mrhead_cc_ground_truth.json" /tmp/cc_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/cc_ground_truth.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_count": $MEASUREMENT_COUNT,
    "measurement_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_values": {
        "total_length_mm": "$REPORTED_LENGTH",
        "genu_thickness_mm": "$REPORTED_GENU",
        "body_thickness_mm": "$REPORTED_BODY",
        "splenium_thickness_mm": "$REPORTED_SPLENIUM",
        "atrophy_classification": "$REPORTED_CLASSIFICATION"
    },
    "sagittal_slice_offset": "$SAGITTAL_SLICE",
    "screenshot_exists": $([ -f "/tmp/cc_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/cc_task_result.json 2>/dev/null || sudo rm -f /tmp/cc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cc_task_result.json
chmod 666 /tmp/cc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/cc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy measurement and report files
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_cc_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_cc_measurements.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_cc_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_cc_report.json 2>/dev/null || true
fi

echo ""
echo "Export result:"
cat /tmp/cc_task_result.json
echo ""
echo "=== Export Complete ==="