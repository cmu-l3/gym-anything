#!/bin/bash
echo "=== Exporting Verify Anatomical Orientation Result ==="

source /workspace/scripts/task_utils.sh

# Get case ID
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MARKUPS="$AMOS_DIR/orientation_markers.mrk.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Try to export fiducials from Slicer
echo "Exporting fiducial data from Slicer..."

if [ "$SLICER_RUNNING" = "true" ]; then
    cat > /tmp/export_fiducials.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Get all fiducial/point markup nodes
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial markup node(s)")

all_fiducials = []

for node in fiducial_nodes:
    node_name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node_name}' has {n_points} control point(s)")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        fiducial = {
            "node_name": node_name,
            "point_index": i,
            "label": label,
            "position_ras": pos,
            "r": pos[0],
            "a": pos[1],
            "s": pos[2]
        }
        all_fiducials.append(fiducial)
        print(f"    Point {i}: '{label}' at RAS ({pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f})")

# Save all fiducials to JSON
fiducials_path = os.path.join(output_dir, "all_fiducials.json")
with open(fiducials_path, "w") as f:
    json.dump({"fiducials": all_fiducials, "count": len(all_fiducials)}, f, indent=2)
print(f"Exported {len(all_fiducials)} fiducial(s) to {fiducials_path}")

# Try to save as markup file
for node in fiducial_nodes:
    try:
        markup_path = os.path.join(output_dir, "orientation_markers.mrk.json")
        slicer.util.saveNode(node, markup_path)
        print(f"Saved markup node to {markup_path}")
    except Exception as e:
        print(f"Could not save markup node: {e}")

# Also check for line markups (in case user created rulers instead)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup node(s)")

print("Export complete")
PYEOF

    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_fiducials.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in {1..15}; do
        if ! kill -0 $EXPORT_PID 2>/dev/null; then
            break
        fi
        sleep 1
    done
    kill $EXPORT_PID 2>/dev/null || true
    
    echo "Slicer export log:"
    cat /tmp/slicer_export.log 2>/dev/null || echo "(no log)"
fi

# Parse fiducial data
FIDUCIALS_FILE="$AMOS_DIR/all_fiducials.json"
FIDUCIAL_COUNT=0
LIVER_FIDUCIAL=""
SPINE_FIDUCIAL=""
HEART_FIDUCIAL=""

if [ -f "$FIDUCIALS_FILE" ]; then
    echo ""
    echo "Parsing fiducial data..."
    
    FIDUCIAL_COUNT=$(python3 -c "
import json
with open('$FIDUCIALS_FILE') as f:
    data = json.load(f)
print(data.get('count', 0))
" 2>/dev/null || echo "0")
    
    echo "Total fiducials found: $FIDUCIAL_COUNT"
    
    # Extract liver fiducial
    LIVER_FIDUCIAL=$(python3 -c "
import json
with open('$FIDUCIALS_FILE') as f:
    data = json.load(f)
for fid in data.get('fiducials', []):
    label = (fid.get('label', '') + ' ' + fid.get('node_name', '')).lower()
    if 'liver' in label:
        print(json.dumps(fid))
        break
" 2>/dev/null || echo "")
    
    # Extract spine fiducial
    SPINE_FIDUCIAL=$(python3 -c "
import json
with open('$FIDUCIALS_FILE') as f:
    data = json.load(f)
for fid in data.get('fiducials', []):
    label = (fid.get('label', '') + ' ' + fid.get('node_name', '')).lower()
    if 'spine' in label or 'vertebr' in label:
        print(json.dumps(fid))
        break
" 2>/dev/null || echo "")
    
    # Extract heart fiducial
    HEART_FIDUCIAL=$(python3 -c "
import json
with open('$FIDUCIALS_FILE') as f:
    data = json.load(f)
for fid in data.get('fiducials', []):
    label = (fid.get('label', '') + ' ' + fid.get('node_name', '')).lower()
    if 'heart' in label or 'cardiac' in label:
        print(json.dumps(fid))
        break
" 2>/dev/null || echo "")
    
    echo "Liver fiducial: ${LIVER_FIDUCIAL:-not found}"
    echo "Spine fiducial: ${SPINE_FIDUCIAL:-not found}"
    echo "Heart fiducial: ${HEART_FIDUCIAL:-not found}"
fi

# Check if markups were created during task
MARKUPS_CREATED="false"
if [ -f "$OUTPUT_MARKUPS" ]; then
    MARKUP_MTIME=$(stat -c %Y "$OUTPUT_MARKUPS" 2>/dev/null || echo "0")
    if [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
        MARKUPS_CREATED="true"
    fi
fi

# Also check if any fiducials were created during task
FIDUCIALS_CREATED="false"
if [ "$FIDUCIAL_COUNT" -gt 0 ] && [ -f "$FIDUCIALS_FILE" ]; then
    FIDUCIALS_MTIME=$(stat -c %Y "$FIDUCIALS_FILE" 2>/dev/null || echo "0")
    if [ "$FIDUCIALS_MTIME" -gt "$TASK_START" ]; then
        FIDUCIALS_CREATED="true"
    fi
fi

# Get reference data
REFERENCE_FILE="/tmp/orientation_reference.json"
HAS_REFERENCE="false"
if [ -f "$REFERENCE_FILE" ]; then
    HAS_REFERENCE="true"
fi

# Create result JSON
echo ""
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "slicer_was_running": $([[ "$SLICER_RUNNING" == "true" ]] && echo "true" || echo "false"),
    "markups_file_exists": $([[ -f "$OUTPUT_MARKUPS" ]] && echo "true" || echo "false"),
    "markups_created_during_task": $([[ "$MARKUPS_CREATED" == "true" ]] && echo "true" || echo "false"),
    "fiducials_created_during_task": $([[ "$FIDUCIALS_CREATED" == "true" ]] && echo "true" || echo "false"),
    "total_fiducial_count": $FIDUCIAL_COUNT,
    "has_reference": $([[ "$HAS_REFERENCE" == "true" ]] && echo "true" || echo "false"),
    "fiducials": {
        "liver": None,
        "spine": None,
        "heart": None
    }
}

# Parse fiducial data
liver_json = '''$LIVER_FIDUCIAL'''
spine_json = '''$SPINE_FIDUCIAL'''
heart_json = '''$HEART_FIDUCIAL'''

try:
    if liver_json.strip():
        result["fiducials"]["liver"] = json.loads(liver_json)
except:
    pass

try:
    if spine_json.strip():
        result["fiducials"]["spine"] = json.loads(spine_json)
except:
    pass

try:
    if heart_json.strip():
        result["fiducials"]["heart"] = json.loads(heart_json)
except:
    pass

# Count found fiducials
result["liver_found"] = result["fiducials"]["liver"] is not None
result["spine_found"] = result["fiducials"]["spine"] is not None
result["heart_found"] = result["fiducials"]["heart"] is not None
result["fiducials_found_count"] = sum([result["liver_found"], result["spine_found"], result["heart_found"]])

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON created")
PYEOF

# Move to final location
rm -f /tmp/orientation_task_result.json 2>/dev/null || sudo rm -f /tmp/orientation_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/orientation_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/orientation_task_result.json
chmod 666 /tmp/orientation_task_result.json 2>/dev/null || sudo chmod 666 /tmp/orientation_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy reference for verifier
if [ -f "$REFERENCE_FILE" ]; then
    cp "$REFERENCE_FILE" /tmp/orientation_reference.json 2>/dev/null || true
    chmod 666 /tmp/orientation_reference.json 2>/dev/null || true
fi

echo ""
echo "Result saved to /tmp/orientation_task_result.json"
cat /tmp/orientation_task_result.json
echo ""
echo "=== Export Complete ==="