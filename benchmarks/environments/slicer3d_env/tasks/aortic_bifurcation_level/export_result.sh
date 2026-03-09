#!/bin/bash
echo "=== Exporting Aortic Bifurcation Level Result ==="

source /workspace/scripts/task_utils.sh

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MARKER="$AMOS_DIR/bifurcation_marker.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/bifurcation_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/bifurcation_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export markups from Slicer before closing
    cat > /tmp/export_bifurcation_markups.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Export all fiducial markups
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial node(s)")

for node in fiducial_nodes:
    node_name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points > 0:
        # Save the markup node to JSON
        output_path = os.path.join(output_dir, f"{node_name}.mrk.json")
        slicer.util.saveNode(node, output_path)
        print(f"Exported {node_name} to {output_path}")
        
        # Also save to the expected output path
        expected_path = os.path.join(output_dir, "bifurcation_marker.mrk.json")
        slicer.util.saveNode(node, expected_path)
        print(f"Also saved to {expected_path}")

# Export all line measurements (in case agent used ruler)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line node(s)")

for node in line_nodes:
    node_name = node.GetName()
    output_path = os.path.join(output_dir, f"{node_name}_line.mrk.json")
    slicer.util.saveNode(node, output_path)
    print(f"Exported line {node_name} to {output_path}")

print("Markup export complete")
PYEOF

    # Run the export script in Slicer (with timeout)
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_bifurcation_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check if agent saved marker file
MARKER_EXISTS="false"
MARKER_PATH=""
MARKER_COORDS=""
MARKER_CREATED_DURING_TASK="false"

POSSIBLE_MARKER_PATHS=(
    "$OUTPUT_MARKER"
    "$AMOS_DIR/bifurcation_marker.mrk.json"
    "$AMOS_DIR/F.mrk.json"
    "$AMOS_DIR/Fiducial.mrk.json"
    "$AMOS_DIR/MarkupsFiducial.mrk.json"
    "/home/ga/Documents/bifurcation_marker.mrk.json"
)

for path in "${POSSIBLE_MARKER_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKER_EXISTS="true"
        MARKER_PATH="$path"
        echo "Found marker at: $path"
        
        # Check if file was created during task
        MARKER_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MARKER_MTIME" -gt "$TASK_START" ]; then
            MARKER_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MARKER" ]; then
            cp "$path" "$OUTPUT_MARKER" 2>/dev/null || true
        fi
        
        # Try to extract coordinates from marker
        MARKER_COORDS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)

# Handle Slicer markup format
if 'markups' in data:
    for markup in data['markups']:
        if 'controlPoints' in markup:
            for cp in markup['controlPoints']:
                if 'position' in cp:
                    print(','.join(map(str, cp['position'])))
                    break
            break
" 2>/dev/null || echo "")
        break
    fi
done

# Check if agent saved a report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_LEVEL=""
REPORTED_DIAMETER=""
HAS_CLINICAL_COMMENT="false"
REPORT_CREATED_DURING_TASK="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/bifurcation_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/bifurcation_report.json"
    "/home/ga/bifurcation_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Check if file was created during task
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_LEVEL=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
level = d.get('vertebral_level', d.get('level', d.get('vertebra', '')))
print(level.upper() if level else '')
" 2>/dev/null || echo "")
        
        REPORTED_DIAMETER=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
diam = d.get('terminal_diameter_mm', d.get('diameter_mm', d.get('diameter', '')))
print(diam if diam else '')
" 2>/dev/null || echo "")
        
        # Check for clinical comment
        HAS_COMMENT=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
comment = d.get('clinical_comment', d.get('comment', d.get('notes', '')))
print('true' if comment and len(str(comment)) > 10 else 'false')
" 2>/dev/null || echo "false")
        HAS_CLINICAL_COMMENT="$HAS_COMMENT"
        
        echo "Reported vertebral level: $REPORTED_LEVEL"
        echo "Reported diameter: $REPORTED_DIAMETER mm"
        echo "Has clinical comment: $HAS_CLINICAL_COMMENT"
        break
    fi
done

# Copy ground truth for verification
echo "Copying ground truth for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_bifurcation_gt.json" /tmp/bifurcation_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/bifurcation_ground_truth.json 2>/dev/null || true

# Copy marker file for verification
if [ -f "$OUTPUT_MARKER" ]; then
    cp "$OUTPUT_MARKER" /tmp/agent_marker.mrk.json 2>/dev/null || true
    chmod 644 /tmp/agent_marker.mrk.json 2>/dev/null || true
fi

# Copy report file for verification
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "marker_exists": $MARKER_EXISTS,
    "marker_path": "$MARKER_PATH",
    "marker_coords": "$MARKER_COORDS",
    "marker_created_during_task": $MARKER_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_vertebral_level": "$REPORTED_LEVEL",
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "has_clinical_comment": $HAS_CLINICAL_COMMENT,
    "screenshot_exists": $([ -f "/tmp/bifurcation_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/bifurcation_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/bifurcation_task_result.json 2>/dev/null || sudo rm -f /tmp/bifurcation_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bifurcation_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bifurcation_task_result.json
chmod 666 /tmp/bifurcation_task_result.json 2>/dev/null || sudo chmod 666 /tmp/bifurcation_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/bifurcation_task_result.json
echo ""
echo "=== Export Complete ==="