#!/bin/bash
echo "=== Exporting Fiducial Volume Registration Result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/registration_result.json"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
TASK_DATA_DIR="/home/ga/Documents/SlicerData/RegistrationTask"

mkdir -p "$SCREENSHOT_DIR"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
FINAL_SCREENSHOT="$SCREENSHOT_DIR/registration_final_$(date +%Y%m%d_%H%M%S).png"
take_screenshot "$FINAL_SCREENSHOT" ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Create query script to extract registration state from Slicer
QUERY_SCRIPT="/tmp/query_registration_state.py"
cat > "$QUERY_SCRIPT" << 'QUERYPY'
import slicer
import json
import os
import math

result = {
    "slicer_running": True,
    "volumes_loaded": [],
    "transforms": [],
    "fiducials": [],
    "registration_applied": False,
    "moving_volume_has_transform": False,
    "transform_matrix": None,
    "fre_mm": None,
    "total_fiducial_points": 0,
    "fiducial_lists_count": 0
}

print("Querying Slicer registration state...")

# Get all volume nodes
for node in slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode"):
    vol_info = {
        "name": node.GetName(),
        "id": node.GetID(),
        "has_parent_transform": node.GetParentTransformNode() is not None
    }
    if node.GetParentTransformNode():
        vol_info["parent_transform_name"] = node.GetParentTransformNode().GetName()
        vol_info["parent_transform_id"] = node.GetParentTransformNode().GetID()
    result["volumes_loaded"].append(vol_info)
    
    # Check if misaligned volume has transform applied
    if "misaligned" in node.GetName().lower():
        if node.GetParentTransformNode() is not None:
            result["moving_volume_has_transform"] = True
            result["registration_applied"] = True
            print(f"Moving volume '{node.GetName()}' has transform applied")

# Get all transform nodes
for node in slicer.util.getNodesByClass("vtkMRMLLinearTransformNode"):
    transform_info = {
        "name": node.GetName(),
        "id": node.GetID()
    }
    
    # Get transform matrix
    import numpy as np
    matrix = slicer.util.arrayFromTransformMatrix(node)
    transform_info["matrix"] = matrix.tolist()
    
    # Extract rotation and translation
    rotation_matrix = matrix[:3, :3]
    translation = matrix[:3, 3]
    transform_info["translation_mm"] = translation.tolist()
    
    # Calculate rotation angles
    try:
        from scipy.spatial.transform import Rotation
        r = Rotation.from_matrix(rotation_matrix)
        euler_deg = r.as_euler('xyz', degrees=True)
        transform_info["rotation_deg"] = euler_deg.tolist()
    except Exception as e:
        # Fallback: approximate rotation angle from trace
        trace = np.trace(rotation_matrix)
        angle_rad = np.arccos(np.clip((trace - 1) / 2, -1, 1))
        transform_info["rotation_deg"] = [0, 0, np.degrees(angle_rad)]
        transform_info["rotation_parse_error"] = str(e)
    
    result["transforms"].append(transform_info)
    
    # Use first transform as the registration result
    if result["transform_matrix"] is None:
        result["transform_matrix"] = matrix.tolist()

print(f"Found {len(result['transforms'])} transform node(s)")

# Get all fiducial nodes
for node in slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode"):
    fid_info = {
        "name": node.GetName(),
        "id": node.GetID(),
        "num_points": node.GetNumberOfControlPoints(),
        "points": []
    }
    
    for i in range(node.GetNumberOfControlPoints()):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        fid_info["points"].append({
            "index": i,
            "label": label,
            "position_ras": pos
        })
    
    result["fiducials"].append(fid_info)
    result["total_fiducial_points"] += fid_info["num_points"]

result["fiducial_lists_count"] = len(result["fiducials"])
print(f"Found {result['fiducial_lists_count']} fiducial list(s) with {result['total_fiducial_points']} total points")

# Try to calculate FRE if we have corresponding fiducial pairs
if len(result["fiducials"]) >= 2 and result["transform_matrix"] is not None:
    try:
        import numpy as np
        
        # Find fixed and moving fiducial lists
        fixed_fids = None
        moving_fids = None
        
        for fid in result["fiducials"]:
            name_lower = fid["name"].lower()
            if any(x in name_lower for x in ["fixed", "reference", "f-", "from"]):
                fixed_fids = fid["points"]
            elif any(x in name_lower for x in ["moving", "misaligned", "m-", "to"]):
                moving_fids = fid["points"]
        
        # If naming convention not found, use first two lists
        if fixed_fids is None and moving_fids is None and len(result["fiducials"]) >= 2:
            fixed_fids = result["fiducials"][0]["points"]
            moving_fids = result["fiducials"][1]["points"]
        
        if fixed_fids and moving_fids:
            n_pairs = min(len(fixed_fids), len(moving_fids))
            if n_pairs >= 3:
                matrix = np.array(result["transform_matrix"])
                total_squared_error = 0
                
                for i in range(n_pairs):
                    f_pos = np.array(fixed_fids[i]["position_ras"])
                    m_pos = np.array(moving_fids[i]["position_ras"])
                    
                    # Transform moving point
                    m_homo = np.append(m_pos, 1)
                    m_transformed = (matrix @ m_homo)[:3]
                    
                    # Calculate error
                    error = np.linalg.norm(f_pos - m_transformed)
                    total_squared_error += error ** 2
                
                fre = math.sqrt(total_squared_error / n_pairs)
                result["fre_mm"] = round(fre, 4)
                result["fre_num_pairs"] = n_pairs
                print(f"Calculated FRE: {fre:.4f} mm from {n_pairs} pairs")
    except Exception as e:
        result["fre_calculation_error"] = str(e)
        print(f"FRE calculation error: {e}")

# Save result
output_path = "/tmp/slicer_registration_state.json"
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Registration state saved to {output_path}")
QUERYPY

chmod 644 "$QUERY_SCRIPT"

# Execute query in Slicer if running
SLICER_STATE_FILE="/tmp/slicer_registration_state.json"
rm -f "$SLICER_STATE_FILE" 2>/dev/null || true

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer state..."
    
    # Run the query script
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$QUERY_SCRIPT" --no-main-window > /tmp/slicer_query.log 2>&1 &
    QUERY_PID=$!
    
    # Wait for query to complete
    sleep 15
    
    # Kill if still running
    kill $QUERY_PID 2>/dev/null || true
    wait $QUERY_PID 2>/dev/null || true
fi

# Build final result JSON
python3 << PYEOF
import json
import os

result = {
    "task_id": "fiducial_volume_registration@1",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $( [ "$SLICER_RUNNING" = "true" ] && echo "true" || echo "false" ),
    "screenshot_exists": os.path.exists("$FINAL_SCREENSHOT"),
    "screenshot_path": "$FINAL_SCREENSHOT" if os.path.exists("$FINAL_SCREENSHOT") else None,
}

# Load Slicer query results
slicer_state_file = "$SLICER_STATE_FILE"
if os.path.exists(slicer_state_file):
    try:
        with open(slicer_state_file, 'r') as f:
            slicer_state = json.load(f)
        result.update(slicer_state)
        print("Loaded Slicer state successfully")
    except Exception as e:
        result["slicer_state_error"] = str(e)
        print(f"Error loading Slicer state: {e}")
else:
    result["slicer_state_error"] = "State file not found"
    print("Slicer state file not found")

# Check for ground truth
gt_path = "/var/lib/slicer/ground_truth/registration_gt.json"
result["ground_truth_available"] = os.path.exists(gt_path)

# Calculate some summary metrics
transforms = result.get("transforms", [])
fiducials = result.get("fiducials", [])

result["num_transforms"] = len(transforms)
result["num_fiducial_lists"] = len(fiducials)

# Count minimum fiducial pairs (smallest list size among the two largest lists)
if len(fiducials) >= 2:
    counts = sorted([f.get("num_points", 0) for f in fiducials], reverse=True)
    result["fiducial_pairs"] = min(counts[0], counts[1]) if len(counts) >= 2 else 0
else:
    result["fiducial_pairs"] = 0

# Save final result
output_file = "$RESULT_FILE"
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"\nResult saved to {output_file}")
print(json.dumps(result, indent=2))
PYEOF

# Set permissions on result file
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
echo "Result file: $RESULT_FILE"
cat "$RESULT_FILE" 2>/dev/null || true