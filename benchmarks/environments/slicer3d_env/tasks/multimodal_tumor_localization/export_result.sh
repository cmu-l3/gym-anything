#!/bin/bash
echo "=== Exporting Multi-Modal Tumor Localization Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/task_sample_id.txt ]; then
    SAMPLE_ID=$(cat /tmp/task_sample_id.txt)
elif [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MARKUP="$BRATS_DIR/tumor_center.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/localization_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_evidence/final_state.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export any unsaved markups from Slicer
    cat > /tmp/export_markups.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Find all fiducial/point markup nodes
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial markup node(s)")

for node in fiducial_nodes:
    name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{name}' has {n_points} control point(s)")
    
    if n_points > 0:
        # Save the node
        output_path = os.path.join(output_dir, f"{name}.mrk.json")
        success = slicer.util.saveNode(node, output_path)
        print(f"    Saved to {output_path}: {success}")
        
        # Also save to expected location if this might be the tumor center
        if 'tumor' in name.lower() or 'center' in name.lower() or n_points == 1:
            expected_path = os.path.join(output_dir, "tumor_center.mrk.json")
            slicer.util.saveNode(node, expected_path)
            print(f"    Also saved to {expected_path}")

# If no fiducial nodes but there are point list nodes
point_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsNode")
for node in point_nodes:
    if node.GetClassName() == "vtkMRMLMarkupsFiducialNode":
        continue  # Already handled
    name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    if n_points > 0:
        print(f"  Found other markup '{name}' with {n_points} points")
        output_path = os.path.join(output_dir, f"{name}.mrk.json")
        slicer.util.saveNode(node, output_path)

print("Markup export complete")
PYEOF

    # Run the export script
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/export_markups.py > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check for markup file
MARKUP_EXISTS="false"
MARKUP_VALID="false"
MARKUP_CREATED_AFTER_START="false"
FIDUCIAL_LABEL=""
FIDUCIAL_R=""
FIDUCIAL_A=""
FIDUCIAL_S=""

# Search for markup file in multiple locations
POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MARKUP"
    "$BRATS_DIR/TumorCenter.mrk.json"
    "$BRATS_DIR/tumorcenter.mrk.json"
    "$BRATS_DIR/Tumor_Center.mrk.json"
    "$BRATS_DIR/F.mrk.json"
    "/home/ga/Documents/tumor_center.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        echo "Found markup at: $path"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_MARKUP" ]; then
            cp "$path" "$OUTPUT_MARKUP" 2>/dev/null || true
        fi
        
        # Check timestamp
        MARKUP_TIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MARKUP_TIME" -gt "$TASK_START" ]; then
            MARKUP_CREATED_AFTER_START="true"
            echo "Markup created during task (timestamp: $MARKUP_TIME > $TASK_START)"
        fi
        
        # Parse markup file to extract coordinates
        python3 << PYEOF
import json
import os

markup_path = "$path"
try:
    with open(markup_path, 'r') as f:
        data = json.load(f)
    
    markups = data.get('markups', [])
    if markups:
        control_points = markups[0].get('controlPoints', [])
        if control_points:
            # Find TumorCenter or use first point
            target_point = None
            for pt in control_points:
                label = pt.get('label', '').lower()
                if 'tumor' in label or 'center' in label:
                    target_point = pt
                    break
            if target_point is None:
                target_point = control_points[0]
            
            position = target_point.get('position', [0, 0, 0])
            label = target_point.get('label', 'Unknown')
            
            print(f"FIDUCIAL_VALID=true")
            print(f"FIDUCIAL_LABEL={label}")
            print(f"FIDUCIAL_R={position[0]}")
            print(f"FIDUCIAL_A={position[1]}")
            print(f"FIDUCIAL_S={position[2]}")
        else:
            print("FIDUCIAL_VALID=false")
    else:
        print("FIDUCIAL_VALID=false")
except Exception as e:
    print(f"FIDUCIAL_VALID=false")
    print(f"# Error: {e}")
PYEOF
        
        # Capture output and parse
        MARKUP_OUTPUT=$(python3 << PYEOF2
import json
try:
    with open("$path", 'r') as f:
        data = json.load(f)
    markups = data.get('markups', [])
    if markups:
        control_points = markups[0].get('controlPoints', [])
        if control_points:
            target_point = None
            for pt in control_points:
                label = pt.get('label', '').lower()
                if 'tumor' in label or 'center' in label:
                    target_point = pt
                    break
            if target_point is None:
                target_point = control_points[0]
            position = target_point.get('position', [0, 0, 0])
            label = target_point.get('label', 'Unknown')
            print(f"{label}|{position[0]}|{position[1]}|{position[2]}")
except:
    print("|||")
PYEOF2
)
        
        if [ -n "$MARKUP_OUTPUT" ] && [ "$MARKUP_OUTPUT" != "|||" ]; then
            MARKUP_VALID="true"
            FIDUCIAL_LABEL=$(echo "$MARKUP_OUTPUT" | cut -d'|' -f1)
            FIDUCIAL_R=$(echo "$MARKUP_OUTPUT" | cut -d'|' -f2)
            FIDUCIAL_A=$(echo "$MARKUP_OUTPUT" | cut -d'|' -f3)
            FIDUCIAL_S=$(echo "$MARKUP_OUTPUT" | cut -d'|' -f4)
            echo "Parsed fiducial: label='$FIDUCIAL_LABEL', R=$FIDUCIAL_R, A=$FIDUCIAL_A, S=$FIDUCIAL_S"
        fi
        
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_CREATED_AFTER_START="false"
REPORT_R=""
REPORT_A=""
REPORT_S=""
REPORT_MODALITY=""
REPORT_OBSERVATIONS=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/tumor_report.json"
    "/home/ga/Documents/localization_report.json"
    "/home/ga/localization_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Check timestamp
        REPORT_TIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_TIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_AFTER_START="true"
        fi
        
        # Parse report
        REPORT_OUTPUT=$(python3 << PYEOF3
import json
try:
    with open("$path", 'r') as f:
        data = json.load(f)
    
    # Extract coordinates (various possible formats)
    r = data.get('R', data.get('r', data.get('x', '')))
    a = data.get('A', data.get('a', data.get('y', '')))
    s = data.get('S', data.get('s', data.get('z', '')))
    
    # Check for nested coordinates
    if not r and 'coordinates' in data:
        coords = data['coordinates']
        if isinstance(coords, list) and len(coords) >= 3:
            r, a, s = coords[0], coords[1], coords[2]
        elif isinstance(coords, dict):
            r = coords.get('R', coords.get('r', ''))
            a = coords.get('A', coords.get('a', ''))
            s = coords.get('S', coords.get('s', ''))
    
    if not r and 'ras' in data:
        ras = data['ras']
        if isinstance(ras, list) and len(ras) >= 3:
            r, a, s = ras[0], ras[1], ras[2]
    
    if not r and 'position' in data:
        pos = data['position']
        if isinstance(pos, list) and len(pos) >= 3:
            r, a, s = pos[0], pos[1], pos[2]
    
    modality = data.get('most_helpful_modality', data.get('modality', data.get('helpful_modality', '')))
    observations = data.get('observations', data.get('description', data.get('notes', '')))
    
    has_coords = r != '' and a != '' and s != ''
    print(f"VALID={'true' if has_coords else 'false'}")
    print(f"R={r}")
    print(f"A={a}")
    print(f"S={s}")
    print(f"MODALITY={modality}")
    print(f"HAS_OBS={'true' if observations else 'false'}")
except Exception as e:
    print(f"VALID=false")
    print(f"# Error: {e}")
PYEOF3
)
        
        REPORT_VALID=$(echo "$REPORT_OUTPUT" | grep "^VALID=" | cut -d'=' -f2)
        REPORT_R=$(echo "$REPORT_OUTPUT" | grep "^R=" | cut -d'=' -f2)
        REPORT_A=$(echo "$REPORT_OUTPUT" | grep "^A=" | cut -d'=' -f2)
        REPORT_S=$(echo "$REPORT_OUTPUT" | grep "^S=" | cut -d'=' -f2)
        REPORT_MODALITY=$(echo "$REPORT_OUTPUT" | grep "^MODALITY=" | cut -d'=' -f2)
        REPORT_HAS_OBS=$(echo "$REPORT_OUTPUT" | grep "^HAS_OBS=" | cut -d'=' -f2)
        
        echo "Parsed report: valid=$REPORT_VALID, R=$REPORT_R, A=$REPORT_A, S=$REPORT_S"
        
        break
    fi
done

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_centroid_gt.json" /tmp/ground_truth_centroid.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/ground_truth_seg.nii.gz 2>/dev/null || true
chmod 644 /tmp/ground_truth_centroid.json /tmp/ground_truth_seg.nii.gz 2>/dev/null || true

# Copy agent outputs for verifier
cp "$OUTPUT_MARKUP" /tmp/agent_markup.json 2>/dev/null || true
cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
chmod 644 /tmp/agent_markup.json /tmp/agent_report.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sample_id": "$SAMPLE_ID",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "markup_exists": $MARKUP_EXISTS,
    "markup_valid": $MARKUP_VALID,
    "markup_created_after_start": $MARKUP_CREATED_AFTER_START,
    "fiducial": {
        "label": "$FIDUCIAL_LABEL",
        "R": "$FIDUCIAL_R",
        "A": "$FIDUCIAL_A",
        "S": "$FIDUCIAL_S"
    },
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_created_after_start": $REPORT_CREATED_AFTER_START,
    "report": {
        "R": "$REPORT_R",
        "A": "$REPORT_A",
        "S": "$REPORT_S",
        "modality": "$REPORT_MODALITY",
        "has_observations": $REPORT_HAS_OBS
    },
    "ground_truth_available": $([ -f "/tmp/ground_truth_centroid.json" ] && echo "true" || echo "false"),
    "screenshot_exists": $([ -f "/tmp/task_evidence/final_state.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/localization_task_result.json 2>/dev/null || sudo rm -f /tmp/localization_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/localization_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/localization_task_result.json
chmod 666 /tmp/localization_task_result.json 2>/dev/null || sudo chmod 666 /tmp/localization_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/localization_task_result.json
echo ""
echo "=== Export Complete ==="