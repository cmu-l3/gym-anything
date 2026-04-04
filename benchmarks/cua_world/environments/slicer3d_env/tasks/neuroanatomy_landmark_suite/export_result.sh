#!/bin/bash
echo "=== Exporting Neuroanatomy Landmark Documentation Result ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
OUTPUT_FIDUCIALS="$SAMPLE_DIR/neuroanatomy_landmarks.mrk.json"
OUTPUT_REPORT="$SAMPLE_DIR/neuroanatomy_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record export time
EXPORT_TIME=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/neuroanatomy_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export fiducials from Slicer
    cat > /tmp/export_neuroanatomy_fiducials.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/SampleData"
os.makedirs(output_dir, exist_ok=True)

all_fiducials = []
all_measurements = []

# Get all fiducial nodes
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}' has {n_points} control points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        fiducial = {
            "node_name": node.GetName(),
            "label": label,
            "index": i,
            "coordinates_ras": pos
        }
        all_fiducials.append(fiducial)
        print(f"    Point {i}: '{label}' at RAS {pos}")

# Get all line/ruler nodes for measurements
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler node(s)")

for node in line_nodes:
    if node.GetNumberOfControlPoints() >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1_ras": p1,
            "p2_ras": p2
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm")

# Save fiducials
if all_fiducials or all_measurements:
    export_data = {
        "fiducials": all_fiducials,
        "measurements": all_measurements,
        "exported_from_slicer": True
    }
    
    fid_path = os.path.join(output_dir, "neuroanatomy_landmarks.mrk.json")
    with open(fid_path, "w") as f:
        json.dump(export_data, f, indent=2)
    print(f"Exported to {fid_path}")
    
    # Also try to save native markup format
    for node in fid_nodes:
        try:
            native_path = os.path.join(output_dir, f"{node.GetName()}_native.mrk.json")
            slicer.util.saveNode(node, native_path)
        except:
            pass
else:
    print("No fiducials or measurements found to export")

print("Export complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_neuroanatomy_fiducials.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_neuroanatomy_fiducials" 2>/dev/null || true
fi

# Check for fiducials file
FIDUCIALS_EXIST="false"
FIDUCIALS_PATH=""
FIDUCIAL_COUNT=0
MEASUREMENT_COUNT=0

POSSIBLE_FID_PATHS=(
    "$OUTPUT_FIDUCIALS"
    "$SAMPLE_DIR/neuroanatomy_landmarks.mrk.json"
    "$SAMPLE_DIR/landmarks.mrk.json"
    "$SAMPLE_DIR/fiducials.mrk.json"
    "/home/ga/Documents/neuroanatomy_landmarks.mrk.json"
    "/home/ga/neuroanatomy_landmarks.mrk.json"
)

for path in "${POSSIBLE_FID_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FIDUCIALS_EXIST="true"
        FIDUCIALS_PATH="$path"
        echo "Found fiducials at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_FIDUCIALS" ]; then
            cp "$path" "$OUTPUT_FIDUCIALS" 2>/dev/null || true
        fi
        
        # Count fiducials
        FIDUCIAL_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    # Check different possible structures
    if 'fiducials' in data:
        print(len(data['fiducials']))
    elif 'markups' in data:
        points = data['markups'][0].get('controlPoints', [])
        print(len(points))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
        
        # Count measurements
        MEASUREMENT_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    if 'measurements' in data:
        print(len(data['measurements']))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
        
        echo "Fiducial count: $FIDUCIAL_COUNT"
        echo "Measurement count: $MEASUREMENT_COUNT"
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
STRUCTURES_DOCUMENTED=0

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$SAMPLE_DIR/neuroanatomy_report.json"
    "$SAMPLE_DIR/report.json"
    "/home/ga/Documents/neuroanatomy_report.json"
    "/home/ga/neuroanatomy_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Count documented structures
        STRUCTURES_DOCUMENTED=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    if 'structures' in data:
        print(len(data['structures']))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
        
        echo "Structures documented: $STRUCTURES_DOCUMENTED"
        break
    fi
done

# Check for file timestamps (anti-gaming)
FIDUCIALS_MTIME=0
REPORT_MTIME=0
FILES_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FIDUCIALS" ]; then
    FIDUCIALS_MTIME=$(stat -c %Y "$OUTPUT_FIDUCIALS" 2>/dev/null || echo "0")
    if [ "$FIDUCIALS_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/neuroanatomy_gt.json" /tmp/neuroanatomy_gt.json 2>/dev/null || true
chmod 644 /tmp/neuroanatomy_gt.json 2>/dev/null || true

# Copy agent outputs for verification
if [ -f "$OUTPUT_FIDUCIALS" ]; then
    cp "$OUTPUT_FIDUCIALS" /tmp/agent_fiducials.json 2>/dev/null || true
    chmod 644 /tmp/agent_fiducials.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "fiducials_exist": $FIDUCIALS_EXIST,
    "fiducials_path": "$FIDUCIALS_PATH",
    "fiducial_count": $FIDUCIAL_COUNT,
    "measurement_count": $MEASUREMENT_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "structures_documented": $STRUCTURES_DOCUMENTED,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "task_start_time": $TASK_START,
    "export_time": $EXPORT_TIME,
    "fiducials_mtime": $FIDUCIALS_MTIME,
    "report_mtime": $REPORT_MTIME,
    "screenshot_exists": $([ -f "/tmp/neuroanatomy_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/neuroanatomy_gt.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/neuroanatomy_task_result.json 2>/dev/null || sudo rm -f /tmp/neuroanatomy_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/neuroanatomy_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/neuroanatomy_task_result.json
chmod 666 /tmp/neuroanatomy_task_result.json 2>/dev/null || sudo chmod 666 /tmp/neuroanatomy_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/neuroanatomy_task_result.json
echo ""
echo "=== Export Complete ==="