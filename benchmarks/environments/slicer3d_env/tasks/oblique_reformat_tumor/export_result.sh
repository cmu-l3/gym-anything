#!/bin/bash
echo "=== Exporting Oblique Slice Reformat Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
if [ -f /tmp/task_final.png ]; then
    echo "Final screenshot captured: $(stat -c %s /tmp/task_final.png 2>/dev/null || echo 0) bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ============================================================
# Extract final slice orientation from Slicer
# ============================================================
echo "Extracting final slice orientation..."

cat > /tmp/export_slice_state.py << 'PYEOF'
import slicer
import json
import os
import math
import numpy as np

output = {
    "slicer_running": True,
    "extraction_success": False,
    "final_orientation_name": "",
    "final_slice_normal": [0, 0, 0],
    "final_slice_position": [0, 0, 0],
    "final_matrix": [],
    "is_oblique": False,
    "angle_from_axial_deg": 0,
    "angle_from_sagittal_deg": 0,
    "angle_from_coronal_deg": 0,
    "min_angle_from_standard_deg": 0,
    "tumor_visible": False,
    "tumor_voxels_in_slice": 0,
    "distance_to_tumor_center_mm": 999
}

def angle_between_vectors(v1, v2):
    """Calculate angle between two vectors in degrees."""
    v1 = np.array(v1)
    v2 = np.array(v2)
    v1_norm = v1 / (np.linalg.norm(v1) + 1e-10)
    v2_norm = v2 / (np.linalg.norm(v2) + 1e-10)
    cos_angle = np.clip(np.dot(v1_norm, v2_norm), -1.0, 1.0)
    return math.degrees(math.acos(abs(cos_angle)))

try:
    # Get Red slice node
    red_slice = slicer.mrmlScene.GetNodeByID("vtkMRMLSliceNodeRed")
    if not red_slice:
        layout_manager = slicer.app.layoutManager()
        if layout_manager:
            slice_widget = layout_manager.sliceWidget("Red")
            if slice_widget:
                red_slice = slice_widget.mrmlSliceNode()
    
    if red_slice:
        import vtk
        slice_to_ras = vtk.vtkMatrix4x4()
        red_slice.GetSliceToRAS(slice_to_ras)
        
        # Extract matrix
        matrix = []
        for i in range(4):
            row = []
            for j in range(4):
                row.append(slice_to_ras.GetElement(i, j))
            matrix.append(row)
        output["final_matrix"] = matrix
        
        # Get orientation name
        output["final_orientation_name"] = red_slice.GetOrientation()
        
        # Extract slice normal (third column)
        normal = [matrix[0][2], matrix[1][2], matrix[2][2]]
        output["final_slice_normal"] = normal
        
        # Extract position
        position = [matrix[0][3], matrix[1][3], matrix[2][3]]
        output["final_slice_position"] = position
        
        # Calculate angles from standard orientations
        axial_normal = [0, 0, 1]
        sagittal_normal = [1, 0, 0]
        coronal_normal = [0, 1, 0]
        
        angle_axial = angle_between_vectors(normal, axial_normal)
        angle_sagittal = angle_between_vectors(normal, sagittal_normal)
        angle_coronal = angle_between_vectors(normal, coronal_normal)
        
        output["angle_from_axial_deg"] = round(angle_axial, 2)
        output["angle_from_sagittal_deg"] = round(angle_sagittal, 2)
        output["angle_from_coronal_deg"] = round(angle_coronal, 2)
        
        min_angle = min(angle_axial, angle_sagittal, angle_coronal)
        output["min_angle_from_standard_deg"] = round(min_angle, 2)
        
        # Check if oblique (>15 degrees from all standard)
        output["is_oblique"] = min_angle > 15.0
        
        output["extraction_success"] = True
        print(f"Final orientation: {output['final_orientation_name']}")
        print(f"Slice normal: {normal}")
        print(f"Angles from standard: Axial={angle_axial:.1f}, Sagittal={angle_sagittal:.1f}, Coronal={angle_coronal:.1f}")
        print(f"Is oblique (>15deg from all): {output['is_oblique']}")
        
        # ============================================================
        # Check tumor visibility in slice
        # ============================================================
        try:
            # Load tumor info
            tumor_info_path = "/var/lib/slicer/ground_truth/tumor_info.json"
            with open(tumor_info_path, "r") as f:
                tumor_info = json.load(f)
            
            tumor_centroid_ras = np.array(tumor_info["centroid_ras"])
            slice_position = np.array(position)
            slice_normal_np = np.array(normal)
            
            # Calculate distance from slice plane to tumor centroid
            # Plane equation: n . (p - p0) = 0
            # Distance = |n . (tumor - slice_pos)|
            distance_to_plane = abs(np.dot(slice_normal_np, tumor_centroid_ras - slice_position))
            output["distance_to_tumor_center_mm"] = round(distance_to_plane, 2)
            
            # Check if tumor is visible (slice passes within 10mm of tumor)
            if distance_to_plane < 15:
                output["tumor_visible"] = True
                print(f"Tumor visible: distance to plane = {distance_to_plane:.1f}mm")
            else:
                print(f"Tumor NOT in slice: distance = {distance_to_plane:.1f}mm")
                
        except Exception as e:
            print(f"Could not check tumor visibility: {e}")
    
    else:
        print("ERROR: Could not find Red slice node")
        output["error"] = "No slice node found"

except Exception as e:
    print(f"ERROR: {e}")
    output["error"] = str(e)

# Save result
with open("/tmp/final_slice_state.json", "w") as f:
    json.dump(output, f, indent=2)

print("Final state saved to /tmp/final_slice_state.json")
PYEOF

# Run export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/export_slice_state.py > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in $(seq 1 30); do
        if [ -f /tmp/final_slice_state.json ]; then
            echo "Export completed"
            break
        fi
        sleep 1
    done
    
    # Kill export process if still running
    kill $EXPORT_PID 2>/dev/null || true
fi

# ============================================================
# Load initial and final state, compute changes
# ============================================================
echo "Computing orientation changes..."

python3 << 'PYEOF'
import json
import os
import math
import numpy as np

def angle_between_vectors(v1, v2):
    v1 = np.array(v1)
    v2 = np.array(v2)
    v1_norm = v1 / (np.linalg.norm(v1) + 1e-10)
    v2_norm = v2 / (np.linalg.norm(v2) + 1e-10)
    cos_angle = np.clip(np.dot(v1_norm, v2_norm), -1.0, 1.0)
    return math.degrees(math.acos(abs(cos_angle)))

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "slicer_was_running": os.environ.get("SLICER_RUNNING", "false") == "true",
    "initial_state_recorded": False,
    "final_state_extracted": False,
    "orientation_changed": False,
    "orientation_change_degrees": 0,
    "is_oblique": False,
    "min_angle_from_standard_deg": 0,
    "tumor_visible": False,
    "distance_to_tumor_mm": 999,
    "initial_orientation": "",
    "final_orientation": "",
    "initial_normal": [0, 0, 1],
    "final_normal": [0, 0, 1]
}

# Load initial state
try:
    with open("/tmp/initial_slice_orientation.json", "r") as f:
        initial = json.load(f)
    if initial.get("recorded", False):
        result["initial_state_recorded"] = True
        result["initial_orientation"] = initial.get("orientation_name", "Unknown")
        result["initial_normal"] = initial.get("slice_normal", [0, 0, 1])
except Exception as e:
    print(f"Could not load initial state: {e}")

# Load final state
try:
    with open("/tmp/final_slice_state.json", "r") as f:
        final = json.load(f)
    if final.get("extraction_success", False):
        result["final_state_extracted"] = True
        result["final_orientation"] = final.get("final_orientation_name", "Unknown")
        result["final_normal"] = final.get("final_slice_normal", [0, 0, 1])
        result["is_oblique"] = final.get("is_oblique", False)
        result["min_angle_from_standard_deg"] = final.get("min_angle_from_standard_deg", 0)
        result["tumor_visible"] = final.get("tumor_visible", False)
        result["distance_to_tumor_mm"] = final.get("distance_to_tumor_center_mm", 999)
        result["angle_from_axial_deg"] = final.get("angle_from_axial_deg", 0)
        result["angle_from_sagittal_deg"] = final.get("angle_from_sagittal_deg", 0)
        result["angle_from_coronal_deg"] = final.get("angle_from_coronal_deg", 0)
except Exception as e:
    print(f"Could not load final state: {e}")

# Check if orientation changed
if result["initial_state_recorded"] and result["final_state_extracted"]:
    initial_normal = result["initial_normal"]
    final_normal = result["final_normal"]
    angle_change = angle_between_vectors(initial_normal, final_normal)
    result["orientation_change_degrees"] = round(angle_change, 2)
    result["orientation_changed"] = angle_change > 5.0  # At least 5 degree change
    print(f"Orientation change: {angle_change:.1f} degrees")

# Save combined result
with open("/tmp/oblique_task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result saved to /tmp/oblique_task_result.json")
PYEOF

# Set environment variables for Python script
export TASK_START TASK_END SLICER_RUNNING

# Display result
if [ -f /tmp/oblique_task_result.json ]; then
    echo ""
    echo "=== Task Result ==="
    cat /tmp/oblique_task_result.json
fi

# Ensure result file is readable
chmod 666 /tmp/oblique_task_result.json 2>/dev/null || true
chmod 666 /tmp/final_slice_state.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo ""
echo "=== Export Complete ==="