#!/bin/bash
echo "=== Exporting repair_mesh_3d_print results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/ready_to_print.stl"
INPUT_FILE="/home/ga/Documents/FreeCAD/damaged_bracket.stl"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# ANALYZE MESH RESULT (Run inside container using FreeCAD)
# We calculate metrics here because the container has the geometry engine
# ------------------------------------------------------------------
cat > /tmp/analyze_result.py << 'EOF'
import FreeCAD
import Mesh
import json
import sys
import os

result = {
    "output_exists": False,
    "input_exists": False,
    "is_solid": False,
    "output_facets": 0,
    "input_diagonal": 0.0,
    "output_diagonal": 0.0,
    "scale_ratio": 0.0,
    "volume": 0.0
}

try:
    input_path = "/home/ga/Documents/FreeCAD/damaged_bracket.stl"
    output_path = "/home/ga/Documents/FreeCAD/ready_to_print.stl"
    
    if os.path.exists(input_path):
        result["input_exists"] = True
        mesh_in = Mesh.Mesh()
        mesh_in.read(input_path)
        bbox_in = mesh_in.BoundBox
        # Calculate bounding box diagonal
        diag_in = ((bbox_in.XMax - bbox_in.XMin)**2 + 
                   (bbox_in.YMax - bbox_in.YMin)**2 + 
                   (bbox_in.ZMax - bbox_in.ZMin)**2)**0.5
        result["input_diagonal"] = diag_in

    if os.path.exists(output_path):
        result["output_exists"] = True
        mesh_out = Mesh.Mesh()
        mesh_out.read(output_path)
        
        result["is_solid"] = mesh_out.isSolid()
        result["output_facets"] = mesh_out.CountFacets
        result["volume"] = mesh_out.Volume
        
        bbox_out = mesh_out.BoundBox
        diag_out = ((bbox_out.XMax - bbox_out.XMin)**2 + 
                    (bbox_out.YMax - bbox_out.YMin)**2 + 
                    (bbox_out.ZMax - bbox_out.ZMin)**2)**0.5
        result["output_diagonal"] = diag_out
        
        if result["input_diagonal"] > 0:
            result["scale_ratio"] = diag_out / result["input_diagonal"]

except Exception as e:
    result["error"] = str(e)

# Write result to JSON
with open("/tmp/analysis_data.json", "w") as f:
    json.dump(result, f)
EOF

# Run analysis script
su - ga -c "freecadcmd /tmp/analyze_result.py"

# Merge file timestamp check with analysis data
OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
FILE_NEWER=$([ "$OUTPUT_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")

# Create final JSON
# We read the python output and add the timestamp check
PYTHON_RESULT=$(cat /tmp/analysis_data.json 2>/dev/null || echo "{}")

cat > /tmp/task_result.json << EOF
{
    "timestamp_check": {
        "task_start": $TASK_START,
        "file_mtime": $OUTPUT_MTIME,
        "file_created_during_task": $FILE_NEWER
    },
    "mesh_analysis": $PYTHON_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json