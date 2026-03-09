#!/bin/bash
echo "=== Exporting Apply Manual Transform Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION}s"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SIZE=$(stat -c%s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Create Python script to extract transform information from Slicer
cat > /tmp/export_transform_info.py << 'PYEOF'
import json
import math
import sys
import os

try:
    import slicer
    import numpy as np
    import vtk
    
    result = {
        "slicer_was_running": True,
        "transform_exists": False,
        "transform_count": 0,
        "transform_name": "",
        "transform_is_identity": True,
        "volume_transformed": False,
        "volume_name": "",
        "parent_transform_name": "",
        "rotation_degrees_x": 0.0,
        "rotation_degrees_y": 0.0,
        "rotation_degrees_z": 0.0,
        "rotation_axis": "",
        "dominant_rotation_degrees": 0.0,
        "matrix_values": [],
        "error": ""
    }
    
    # Get all linear transforms
    transforms = slicer.util.getNodesByClass('vtkMRMLLinearTransformNode')
    transform_count = transforms.GetNumberOfItems() if transforms else 0
    result["transform_count"] = transform_count
    
    if transform_count > 0:
        result["transform_exists"] = True
        
        # Find the most recently created transform (likely the user's)
        # Or find one that's applied to a volume
        target_transform = None
        
        for i in range(transform_count):
            transform_node = transforms.GetItemAsObject(i)
            if transform_node:
                # Check if this transform is applied to MRHead
                volumes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
                for j in range(volumes.GetNumberOfItems() if volumes else 0):
                    vol = volumes.GetItemAsObject(j)
                    if vol and vol.GetParentTransformNode() == transform_node:
                        target_transform = transform_node
                        result["volume_transformed"] = True
                        result["volume_name"] = vol.GetName()
                        result["parent_transform_name"] = transform_node.GetName()
                        break
                
                if target_transform is None:
                    target_transform = transform_node
        
        if target_transform:
            result["transform_name"] = target_transform.GetName()
            
            # Get the transform matrix
            matrix = vtk.vtkMatrix4x4()
            target_transform.GetMatrixTransformToParent(matrix)
            
            # Store matrix values
            matrix_list = []
            for row in range(4):
                row_vals = []
                for col in range(4):
                    row_vals.append(matrix.GetElement(row, col))
                matrix_list.append(row_vals)
            result["matrix_values"] = matrix_list
            
            # Check if identity
            is_identity = True
            for row in range(4):
                for col in range(4):
                    expected = 1.0 if row == col else 0.0
                    if abs(matrix.GetElement(row, col) - expected) > 0.001:
                        is_identity = False
                        break
            result["transform_is_identity"] = is_identity
            
            # Extract rotation angles from the rotation matrix (upper-left 3x3)
            # Using the decomposition for rotation around Z (which corresponds to S axis in RAS)
            # R_z(theta) = [[cos, -sin, 0], [sin, cos, 0], [0, 0, 1]]
            
            # Extract rotation matrix components
            r00 = matrix.GetElement(0, 0)
            r01 = matrix.GetElement(0, 1)
            r02 = matrix.GetElement(0, 2)
            r10 = matrix.GetElement(1, 0)
            r11 = matrix.GetElement(1, 1)
            r12 = matrix.GetElement(1, 2)
            r20 = matrix.GetElement(2, 0)
            r21 = matrix.GetElement(2, 1)
            r22 = matrix.GetElement(2, 2)
            
            # Calculate Euler angles (ZYX convention)
            # In RAS coordinates, Z is Superior, so rotation around Z is rotation around S axis
            
            # Check for gimbal lock
            if abs(r20) < 0.9999:
                # Standard case
                rot_y = math.asin(-r20)
                rot_x = math.atan2(r21, r22)
                rot_z = math.atan2(r10, r00)
            else:
                # Gimbal lock
                rot_z = 0
                if r20 < 0:
                    rot_y = math.pi / 2
                    rot_x = math.atan2(r01, r02)
                else:
                    rot_y = -math.pi / 2
                    rot_x = math.atan2(-r01, -r02)
            
            # Convert to degrees
            rot_x_deg = math.degrees(rot_x)
            rot_y_deg = math.degrees(rot_y)
            rot_z_deg = math.degrees(rot_z)
            
            result["rotation_degrees_x"] = round(rot_x_deg, 2)
            result["rotation_degrees_y"] = round(rot_y_deg, 2)
            result["rotation_degrees_z"] = round(rot_z_deg, 2)
            
            # Determine dominant rotation axis
            abs_rotations = {
                "LR": abs(rot_x_deg),  # Left-Right (X)
                "PA": abs(rot_y_deg),  # Posterior-Anterior (Y)
                "IS": abs(rot_z_deg)   # Inferior-Superior (Z/S)
            }
            dominant_axis = max(abs_rotations, key=abs_rotations.get)
            result["rotation_axis"] = dominant_axis
            result["dominant_rotation_degrees"] = abs_rotations[dominant_axis]
    
    # Check if volume exists even without transform
    volumes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    result["volume_loaded"] = False
    for j in range(volumes.GetNumberOfItems() if volumes else 0):
        vol = volumes.GetItemAsObject(j)
        if vol and "MRHead" in vol.GetName():
            result["volume_loaded"] = True
            if not result["volume_name"]:
                result["volume_name"] = vol.GetName()
            break
    
    # Write result
    with open('/tmp/transform_export.json', 'w') as f:
        json.dump(result, f, indent=2)
    
    print("Transform export completed successfully")
    print(json.dumps(result, indent=2))

except Exception as e:
    error_result = {
        "slicer_was_running": True,
        "transform_exists": False,
        "error": str(e)
    }
    with open('/tmp/transform_export.json', 'w') as f:
        json.dump(error_result, f, indent=2)
    print(f"Error during export: {e}")
PYEOF

# Run the export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting transform information from Slicer..."
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_transform_info.py --no-main-window > /tmp/transform_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in {1..20}; do
        if [ -f /tmp/transform_export.json ]; then
            # Check if file has content
            if [ -s /tmp/transform_export.json ]; then
                echo "Export completed"
                break
            fi
        fi
        sleep 1
    done
    
    # Kill if still running
    kill $EXPORT_PID 2>/dev/null || true
fi

# Read exported data or create default
EXPORT_DATA="{}"
if [ -f /tmp/transform_export.json ] && [ -s /tmp/transform_export.json ]; then
    EXPORT_DATA=$(cat /tmp/transform_export.json)
    echo "Exported data:"
    echo "$EXPORT_DATA"
else
    echo "WARNING: No export data found"
    EXPORT_DATA='{"slicer_was_running": false, "transform_exists": false, "error": "Export failed"}'
fi

# Read initial state
INITIAL_STATE="{}"
if [ -f /tmp/transform_initial_state.json ]; then
    INITIAL_STATE=$(cat /tmp/transform_initial_state.json)
fi

# Check if transform was created during the task (anti-gaming)
INITIAL_TRANSFORMS=$(echo "$INITIAL_STATE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('initial_transforms', 0))" 2>/dev/null || echo "0")
FINAL_TRANSFORMS=$(echo "$EXPORT_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transform_count', 0))" 2>/dev/null || echo "0")

TRANSFORM_CREATED_DURING_TASK="false"
if [ "$FINAL_TRANSFORMS" -gt "$INITIAL_TRANSFORMS" ]; then
    TRANSFORM_CREATED_DURING_TASK="true"
fi

# Compile final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF
import json

export_data = $EXPORT_DATA
initial_state = $INITIAL_STATE

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "slicer_was_running": "$SLICER_RUNNING" == "true",
    "transform_created_during_task": "$TRANSFORM_CREATED_DURING_TASK" == "true",
    "initial_transform_count": $INITIAL_TRANSFORMS,
    "final_transform_count": $FINAL_TRANSFORMS,
    "screenshot_path": "/tmp/task_final.png",
    **export_data
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Move to final location
rm -f /tmp/transform_task_result.json 2>/dev/null || sudo rm -f /tmp/transform_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/transform_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/transform_task_result.json
chmod 666 /tmp/transform_task_result.json 2>/dev/null || sudo chmod 666 /tmp/transform_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/transform_task_result.json"
cat /tmp/transform_task_result.json