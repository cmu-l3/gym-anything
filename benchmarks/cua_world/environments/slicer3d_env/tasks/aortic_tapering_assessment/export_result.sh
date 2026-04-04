#!/bin/bash
echo "=== Exporting Aortic Tapering Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/aortic_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/tapering_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/aortic_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from the Slicer scene
    cat > /tmp/export_aortic_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Collect all line/ruler markups
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
        
        # Calculate midpoint (useful for determining level)
        midpoint = [(p1[i] + p2[i])/2 for i in range(3)]
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2],
            "midpoint": [round(x, 2) for x in midpoint],
            "z_coordinate": round(midpoint[2], 2)
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm at z={midpoint[2]:.1f}")

# Collect fiducial markups as well
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        all_measurements.append({
            "name": label,
            "type": "fiducial",
            "position": [round(x, 2) for x in pos],
            "z_coordinate": round(pos[2], 2)
        })
        print(f"  Fiducial '{label}' at z={pos[2]:.1f}")

# Save measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "aortic_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Save individual markup nodes
    for node in line_nodes:
        try:
            mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
            slicer.util.saveNode(node, mrk_path)
        except:
            pass
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_aortic_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_aortic_markups" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASUREMENT_COUNT=0
MEASUREMENT_MTIME="0"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/aortic_measurements.mrk.json"
    "$AMOS_DIR/measurements.mrk.json"
    "/home/ga/Documents/aortic_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        MEASUREMENT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Count measurements
        MEASUREMENT_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    meas = data.get('measurements', [])
    print(len(meas))
except:
    print(0)
" 2>/dev/null || echo "0")
        
        echo "Found measurement file at: $path ($MEASUREMENT_COUNT measurements)"
        
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if measurement file was created during task
MEASUREMENT_CREATED_DURING_TASK="false"
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ "$MEASUREMENT_MTIME" -gt "$TASK_START" ]; then
    MEASUREMENT_CREATED_DURING_TASK="true"
fi

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_MTIME="0"
REPORT_FIELDS=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/tapering_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/aorta_report.json"
    "/home/ga/Documents/tapering_report.json"
    "/home/ga/tapering_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        echo "Found report file at: $path"
        
        # Extract key fields from report
        REPORT_FIELDS=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    fields = []
    for key in ['suprarenal_diameter_mm', 'infrarenal_diameter_mm', 'bifurcation_diameter_mm',
                'infrarenal_suprarenal_ratio', 'bifurcation_suprarenal_ratio',
                'focal_dilation_present', 'focal_dilation_max_diameter_mm',
                'tapering_assessment', 'clinical_recommendation']:
        if key in data:
            fields.append(key)
    print(','.join(fields))
except:
    print('')
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if report was created during task
REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_EXISTS" = "true" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Copy ground truth for verifier (hidden from agent during task)
echo "Preparing verification data..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" /tmp/aortic_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/aortic_ground_truth.json 2>/dev/null || true

# Copy agent outputs for verifier
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_measurements.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Screenshot check
SCREENSHOT_EXISTS="false"
if [ -f /tmp/aortic_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_count": $MEASUREMENT_COUNT,
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_fields": "$REPORT_FIELDS",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/aortic_tapering_result.json 2>/dev/null || sudo rm -f /tmp/aortic_tapering_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aortic_tapering_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/aortic_tapering_result.json
chmod 666 /tmp/aortic_tapering_result.json 2>/dev/null || sudo chmod 666 /tmp/aortic_tapering_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/aortic_tapering_result.json
echo ""

# Display agent report if exists
if [ -f "$OUTPUT_REPORT" ]; then
    echo ""
    echo "Agent Report Content:"
    cat "$OUTPUT_REPORT"
    echo ""
fi

echo "=== Export Complete ==="