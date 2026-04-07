#!/bin/bash
echo "=== Exporting structural_analytical_model_setup result ==="

source /workspace/scripts/task_utils.sh || true

# Take the final screenshot for trajectory/UI validation before data extraction
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/analytical_model_result.json"

# Write the export extraction Python script
cat > /tmp/export_analytical_model.py << 'PYEOF'
import sys
import json
import os

# Ensure ifcopenshell from Bonsai is available
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/analytical_frame.ifc"

# Retrieve task start timestamp
task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

if not os.path.exists(ifc_path):
    result = {
        "file_exists": False,
        "file_mtime": 0.0,
        "n_projects": 0,
        "n_analysis_models": 0,
        "n_point_connections": 0,
        "n_curve_members": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Query analytical structural entities
        projects = ifc.by_type("IfcProject")
        analysis_models = ifc.by_type("IfcStructuralAnalysisModel")
        points = ifc.by_type("IfcStructuralPointConnection")
        curves = ifc.by_type("IfcStructuralCurveMember")
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_projects": len(projects),
            "n_analysis_models": len(analysis_models),
            "n_point_connections": len(points),
            "n_curve_members": len(curves),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_projects": 0,
            "n_analysis_models": 0,
            "n_point_connections": 0,
            "n_curve_members": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run extraction headless using Blender's Python runtime
/opt/blender/blender --background --python /tmp/export_analytical_model.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback if the export failed entirely
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_projects":0,"n_analysis_models":0,"n_point_connections":0,"n_curve_members":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"