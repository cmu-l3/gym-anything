#!/bin/bash
echo "=== Exporting Portal Vein Bifurcation Task Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get patient number
PATIENT_NUM=$(cat /tmp/ircadb_patient_num 2>/dev/null || echo "5")
IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_FIDUCIAL="$IRCADB_DIR/portal_bifurcation.mrk.json"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
fi

# Initialize fiducial data
FIDUCIAL_EXISTS="false"
FIDUCIAL_NAME=""
FIDUCIAL_RAS=""
FIDUCIAL_CREATED_DURING_TASK="false"

# Try to export fiducials from Slicer's scene
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting fiducials from Slicer..."
    
    cat > /tmp/extract_portal_fiducials.py << 'PYEOF'
import json
import os
import math

try:
    import slicer
    
    output_dir = "/home/ga/Documents/SlicerData/IRCADb"
    os.makedirs(output_dir, exist_ok=True)
    
    result = {
        "fiducials": [],
        "portal_bifurcation_found": False,
        "portal_bifurcation_coords": None,
        "portal_bifurcation_name": None
    }
    
    # Get all fiducial nodes
    fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
    
    for node in fiducial_nodes:
        node_name = node.GetName()
        
        for i in range(node.GetNumberOfControlPoints()):
            label = node.GetNthControlPointLabel(i)
            coords = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(i, coords)
            
            fid_info = {
                "node_name": node_name,
                "label": label,
                "ras_coords": coords
            }
            result["fiducials"].append(fid_info)
            
            # Check if this is the portal bifurcation
            name_lower = (label + " " + node_name).lower()
            if "portal" in name_lower or "bifurc" in name_lower or "pv" in name_lower:
                result["portal_bifurcation_found"] = True
                result["portal_bifurcation_coords"] = coords
                result["portal_bifurcation_name"] = label if label else node_name
        
        # Save the node if it's related to portal
        if "portal" in node_name.lower() or "bifurc" in node_name.lower():
            save_path = os.path.join(output_dir, "portal_bifurcation.mrk.json")
            slicer.util.saveNode(node, save_path)
            print(f"Saved portal fiducial to {save_path}")
    
    # If no portal-named fiducial found, use first fiducial
    if not result["portal_bifurcation_found"] and result["fiducials"]:
        result["portal_bifurcation_found"] = True
        result["portal_bifurcation_coords"] = result["fiducials"][0]["ras_coords"]
        result["portal_bifurcation_name"] = result["fiducials"][0]["label"]
    
    # Save extraction result
    with open("/tmp/extracted_fiducials.json", "w") as f:
        json.dump(result, f, indent=2)
    
    print(f"Extracted {len(result['fiducials'])} fiducial(s)")
    if result["portal_bifurcation_found"]:
        print(f"Portal bifurcation found at: {result['portal_bifurcation_coords']}")

except Exception as e:
    print(f"Error extracting fiducials: {e}")
    import traceback
    traceback.print_exc()
PYEOF

    # Run extraction script in Slicer (background process with timeout)
    timeout 30 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_portal_fiducials.py --no-main-window" > /tmp/slicer_extract.log 2>&1 || true
    
    sleep 5
fi

# Read extracted fiducial data
if [ -f /tmp/extracted_fiducials.json ]; then
    echo "Reading extracted fiducial data..."
    EXTRACTED_DATA=$(cat /tmp/extracted_fiducials.json)
    
    PORTAL_FOUND=$(echo "$EXTRACTED_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if d.get('portal_bifurcation_found') else 'false')" 2>/dev/null || echo "false")
    
    if [ "$PORTAL_FOUND" = "true" ]; then
        FIDUCIAL_EXISTS="true"
        FIDUCIAL_RAS=$(echo "$EXTRACTED_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('portal_bifurcation_coords', [])))" 2>/dev/null || echo "[]")
        FIDUCIAL_NAME=$(echo "$EXTRACTED_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('portal_bifurcation_name', ''))" 2>/dev/null || echo "")
    fi
fi

# Also check if fiducial file was saved directly
if [ -f "$OUTPUT_FIDUCIAL" ]; then
    FIDUCIAL_EXISTS="true"
    echo "Found saved fiducial file: $OUTPUT_FIDUCIAL"
    
    # Check if it was created during the task
    FIDUCIAL_MTIME=$(stat -c%Y "$OUTPUT_FIDUCIAL" 2>/dev/null || echo "0")
    if [ "$FIDUCIAL_MTIME" -gt "$TASK_START" ]; then
        FIDUCIAL_CREATED_DURING_TASK="true"
    fi
    
    # Parse fiducial coordinates from file if not already extracted
    if [ -z "$FIDUCIAL_RAS" ] || [ "$FIDUCIAL_RAS" = "[]" ]; then
        FIDUCIAL_RAS=$(python3 << PYEOF
import json
import math

try:
    with open("$OUTPUT_FIDUCIAL") as f:
        data = json.load(f)
    
    # Handle Slicer markup JSON format
    if "markups" in data:
        for markup in data.get("markups", []):
            cps = markup.get("controlPoints", [])
            if cps:
                pos = cps[0].get("position", [0, 0, 0])
                print(json.dumps(pos))
                break
    elif "controlPoints" in data:
        cps = data.get("controlPoints", [])
        if cps:
            pos = cps[0].get("position", [0, 0, 0])
            print(json.dumps(pos))
except Exception as e:
    print("[]")
PYEOF
)
    fi
fi

# Search for any fiducial files created during task
if [ "$FIDUCIAL_EXISTS" = "false" ]; then
    echo "Searching for other fiducial files..."
    FOUND_FIDUCIAL=$(find "$IRCADB_DIR" /home/ga -maxdepth 3 -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    
    if [ -n "$FOUND_FIDUCIAL" ]; then
        echo "Found fiducial file: $FOUND_FIDUCIAL"
        FIDUCIAL_EXISTS="true"
        FIDUCIAL_CREATED_DURING_TASK="true"
        
        FIDUCIAL_RAS=$(python3 << PYEOF
import json
try:
    with open("$FOUND_FIDUCIAL") as f:
        data = json.load(f)
    if "markups" in data:
        for markup in data.get("markups", []):
            cps = markup.get("controlPoints", [])
            if cps:
                print(json.dumps(cps[0].get("position", [])))
                break
except:
    print("[]")
PYEOF
)
    fi
fi

# Load ground truth
GT_FILE="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_portal_bifurcation.json"
GT_RAS="[]"
GT_TOLERANCE="8.0"

if [ -f "$GT_FILE" ]; then
    GT_RAS=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(json.dumps(d.get('bifurcation_ras', [])))" 2>/dev/null || echo "[]")
    GT_TOLERANCE=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(d.get('tolerance_mm', 8.0))" 2>/dev/null || echo "8.0")
fi

# Calculate distance if we have both coordinates
DISTANCE_MM=""
if [ -n "$FIDUCIAL_RAS" ] && [ "$FIDUCIAL_RAS" != "[]" ] && [ "$GT_RAS" != "[]" ]; then
    DISTANCE_MM=$(python3 << PYEOF
import json
import math

try:
    fid = json.loads('$FIDUCIAL_RAS')
    gt = json.loads('$GT_RAS')
    
    if len(fid) == 3 and len(gt) == 3:
        dist = math.sqrt(sum((a - b)**2 for a, b in zip(fid, gt)))
        print(f"{dist:.2f}")
except:
    print("")
PYEOF
)
fi

# Get initial state
INITIAL_EXISTS="false"
if [ -f /tmp/initial_state.json ]; then
    INITIAL_EXISTS=$(python3 -c "import json; d=json.load(open('/tmp/initial_state.json')); print('true' if d.get('fiducial_exists') else 'false')" 2>/dev/null || echo "false")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "fiducial_exists": $FIDUCIAL_EXISTS,
    "fiducial_name": "$FIDUCIAL_NAME",
    "fiducial_ras": $FIDUCIAL_RAS,
    "fiducial_created_during_task": $FIDUCIAL_CREATED_DURING_TASK,
    "initial_fiducial_existed": $INITIAL_EXISTS,
    "ground_truth_ras": $GT_RAS,
    "ground_truth_tolerance_mm": $GT_TOLERANCE,
    "distance_to_gt_mm": "$DISTANCE_MM",
    "patient_num": "$PATIENT_NUM"
}
EOF

# Move to final location
rm -f /tmp/portal_task_result.json 2>/dev/null || sudo rm -f /tmp/portal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/portal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/portal_task_result.json
chmod 666 /tmp/portal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/portal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/portal_task_result.json"
cat /tmp/portal_task_result.json
echo ""
echo "=== Export Complete ==="