#!/bin/bash
echo "=== Exporting Tracheal Carina Localization Results ==="

source /workspace/scripts/task_utils.sh

RESULT_DIR="/tmp/task_result"
RESULT_JSON="$RESULT_DIR/result.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$RESULT_DIR"

# Record task end time
TASK_END_TIME=$(date +%s)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "$TASK_END_TIME")
TASK_DURATION=$((TASK_END_TIME - TASK_START_TIME))

echo "Task duration: ${TASK_DURATION}s"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot "$RESULT_DIR/final_screenshot.png" ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ============================================================
# Extract fiducial data from Slicer
# ============================================================
FIDUCIAL_JSON="$RESULT_DIR/fiducials.json"

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting fiducial data from Slicer..."
    
    # Create extraction script
    EXTRACT_SCRIPT="/tmp/extract_fiducials.py"
    cat > "$EXTRACT_SCRIPT" << 'PYEOF'
import json
import slicer
import os

result = {
    "fiducials_found": [],
    "carina_fiducial": None,
    "total_markups": 0,
    "error": None
}

try:
    # Find all point/fiducial markup nodes
    markup_classes = [
        "vtkMRMLMarkupsFiducialNode",
        "vtkMRMLMarkupsNode"
    ]
    
    for class_name in markup_classes:
        markup_nodes = slicer.mrmlScene.GetNodesByClass(class_name)
        if markup_nodes:
            markup_nodes.UnRegister(None)
            
            for i in range(markup_nodes.GetNumberOfItems()):
                node = markup_nodes.GetItemAsObject(i)
                if node is None:
                    continue
                    
                node_name = node.GetName() if hasattr(node, 'GetName') else ""
                
                # Check if this node has control points
                if not hasattr(node, 'GetNumberOfControlPoints'):
                    continue
                    
                n_points = node.GetNumberOfControlPoints()
                result["total_markups"] += n_points
                
                for j in range(n_points):
                    point_label = ""
                    if hasattr(node, 'GetNthControlPointLabel'):
                        point_label = node.GetNthControlPointLabel(j)
                    
                    point_pos = [0.0, 0.0, 0.0]
                    node.GetNthControlPointPosition(j, point_pos)
                    
                    fiducial_info = {
                        "node_name": node_name,
                        "point_label": point_label,
                        "position_ras": point_pos,
                        "index": j
                    }
                    result["fiducials_found"].append(fiducial_info)
                    
                    # Check if this is the carina fiducial
                    name_lower = f"{node_name}_{point_label}".lower()
                    if "carina" in name_lower or "carina" in node_name.lower() or "carina" in point_label.lower():
                        result["carina_fiducial"] = fiducial_info
                        print(f"Found carina fiducial: {fiducial_info}")

    print(f"Total fiducials found: {len(result['fiducials_found'])}")
    
except Exception as e:
    result["error"] = str(e)
    print(f"Error extracting fiducials: {e}")

# Save result
output_path = "/tmp/task_result/fiducials.json"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Fiducial data saved to {output_path}")
PYEOF

    chmod 644 "$EXTRACT_SCRIPT"
    chown ga:ga "$EXTRACT_SCRIPT"
    
    # Execute extraction script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window \
        --python-script "$EXTRACT_SCRIPT" > /tmp/extract_fiducials.log 2>&1 &
    
    EXTRACT_PID=$!
    
    # Wait for extraction with timeout
    for i in {1..30}; do
        if [ -f "$FIDUCIAL_JSON" ]; then
            echo "Fiducial extraction complete"
            break
        fi
        if ! kill -0 $EXTRACT_PID 2>/dev/null; then
            echo "Extraction process finished"
            break
        fi
        sleep 1
    done
    
    # Kill extraction process if still running
    kill $EXTRACT_PID 2>/dev/null || true
    
    # Cleanup
    rm -f "$EXTRACT_SCRIPT"
fi

# ============================================================
# Fallback: Look for saved markup files
# ============================================================
if [ ! -f "$FIDUCIAL_JSON" ] || [ ! -s "$FIDUCIAL_JSON" ]; then
    echo "Attempting fallback fiducial extraction..."
    
    # Search for any markup files
    MARKUP_FILES=$(find /home/ga -name "*.mrk.json" -o -name "*.fcsv" -mmin -30 2>/dev/null | head -5)
    
    if [ -n "$MARKUP_FILES" ]; then
        echo "Found markup files:"
        echo "$MARKUP_FILES"
        
        # Try to parse the first one
        FIRST_MARKUP=$(echo "$MARKUP_FILES" | head -1)
        if [ -f "$FIRST_MARKUP" ]; then
            python3 << PYEOF
import json
import os

markup_file = "$FIRST_MARKUP"
output_file = "$FIDUCIAL_JSON"

result = {
    "fiducials_found": [],
    "carina_fiducial": None,
    "error": None,
    "source": "saved_file"
}

try:
    with open(markup_file, 'r') as f:
        data = json.load(f)
    
    # Parse Slicer markup format
    if 'markups' in data:
        for markup in data.get('markups', []):
            markup_type = markup.get('type', '')
            for cp in markup.get('controlPoints', []):
                fiducial_info = {
                    "node_name": data.get('name', 'Unknown'),
                    "point_label": cp.get('label', ''),
                    "position_ras": cp.get('position', [0, 0, 0]),
                    "index": cp.get('id', 0)
                }
                result["fiducials_found"].append(fiducial_info)
                
                name_lower = f"{fiducial_info['node_name']}_{fiducial_info['point_label']}".lower()
                if "carina" in name_lower:
                    result["carina_fiducial"] = fiducial_info
    
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Parsed {len(result['fiducials_found'])} fiducials from saved file")
except Exception as e:
    result["error"] = str(e)
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
    print(f"Error parsing markup file: {e}")
PYEOF
        fi
    fi
fi

# Create minimal result if nothing found
if [ ! -f "$FIDUCIAL_JSON" ]; then
    echo "No fiducials found - creating empty result"
    cat > "$FIDUCIAL_JSON" << 'EOF'
{
    "fiducials_found": [],
    "carina_fiducial": null,
    "error": "No fiducials found in scene",
    "total_markups": 0
}
EOF
fi

# ============================================================
# Copy ground truth for verification
# ============================================================
GT_JSON="$GROUND_TRUTH_DIR/carina_location.json"
if [ -f "$GT_JSON" ]; then
    cp "$GT_JSON" "$RESULT_DIR/ground_truth.json" 2>/dev/null || true
fi

# ============================================================
# Build final result JSON
# ============================================================
python3 << PYEOF
import json
import os
import math

result_dir = "$RESULT_DIR"
gt_path = "$GROUND_TRUTH_DIR/carina_location.json"

# Load fiducial data
fiducial_path = os.path.join(result_dir, "fiducials.json")
try:
    with open(fiducial_path, 'r') as f:
        fiducial_data = json.load(f)
except Exception as e:
    fiducial_data = {"fiducials_found": [], "carina_fiducial": None, "error": str(e)}

# Load ground truth
try:
    with open(gt_path, 'r') as f:
        gt_data = json.load(f)
except Exception as e:
    gt_data = {"error": str(e)}

# Compute metrics
metrics = {
    "task_duration_seconds": $TASK_DURATION,
    "slicer_running": $( [ "$SLICER_RUNNING" = "true" ] && echo "true" || echo "false" ),
    "fiducial_exists": len(fiducial_data.get("fiducials_found", [])) > 0,
    "carina_named_correctly": fiducial_data.get("carina_fiducial") is not None,
    "num_fiducials": len(fiducial_data.get("fiducials_found", [])),
    "carina_position_ras": None,
    "distance_from_gt_mm": None,
    "within_tolerance": False,
    "z_coordinate_valid": False,
    "xy_coordinate_valid": False
}

# Get carina fiducial position
carina_fid = fiducial_data.get("carina_fiducial")
if carina_fid:
    pos = carina_fid.get("position_ras", [0, 0, 0])
    metrics["carina_position_ras"] = pos
    
    if gt_data and "carina_ras" in gt_data:
        gt_pos = gt_data.get("carina_ras", [0, 0, 0])
        bounds_min = gt_data.get("bounds_min_ras", [-1000, -1000, -1000])
        bounds_max = gt_data.get("bounds_max_ras", [1000, 1000, 1000])
        
        # Compute Euclidean distance
        dist = math.sqrt(sum((a - b)**2 for a, b in zip(pos, gt_pos)))
        metrics["distance_from_gt_mm"] = round(dist, 2)
        
        # Check if within tolerance bounds
        in_x = bounds_min[0] <= pos[0] <= bounds_max[0]
        in_y = bounds_min[1] <= pos[1] <= bounds_max[1]
        in_z = bounds_min[2] <= pos[2] <= bounds_max[2]
        
        metrics["xy_coordinate_valid"] = in_x and in_y
        metrics["z_coordinate_valid"] = in_z
        metrics["within_tolerance"] = in_x and in_y and in_z
elif fiducial_data.get("fiducials_found"):
    # No carina-named fiducial, but there are fiducials
    # Use the first one for evaluation
    first_fid = fiducial_data["fiducials_found"][0]
    pos = first_fid.get("position_ras", [0, 0, 0])
    metrics["carina_position_ras"] = pos
    
    if gt_data and "carina_ras" in gt_data:
        gt_pos = gt_data.get("carina_ras", [0, 0, 0])
        bounds_min = gt_data.get("bounds_min_ras", [-1000, -1000, -1000])
        bounds_max = gt_data.get("bounds_max_ras", [1000, 1000, 1000])
        
        dist = math.sqrt(sum((a - b)**2 for a, b in zip(pos, gt_pos)))
        metrics["distance_from_gt_mm"] = round(dist, 2)
        
        in_x = bounds_min[0] <= pos[0] <= bounds_max[0]
        in_y = bounds_min[1] <= pos[1] <= bounds_max[1]
        in_z = bounds_min[2] <= pos[2] <= bounds_max[2]
        
        metrics["xy_coordinate_valid"] = in_x and in_y
        metrics["z_coordinate_valid"] = in_z
        metrics["within_tolerance"] = in_x and in_y and in_z

# Save final result
final_result = {
    "fiducial_data": fiducial_data,
    "ground_truth": gt_data,
    "metrics": metrics,
    "screenshot_path": os.path.join(result_dir, "final_screenshot.png"),
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME
}

result_path = os.path.join(result_dir, "result.json")
with open(result_path, 'w') as f:
    json.dump(final_result, f, indent=2)

print("Metrics:")
print(json.dumps(metrics, indent=2))
PYEOF

# Copy result to standard location
cp "$RESULT_JSON" /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "=== Results exported to $RESULT_DIR ==="
cat "$RESULT_JSON" 2>/dev/null || echo "Result JSON not found"