#!/bin/bash
echo "=== Exporting structural_grid_definition result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/grid_definition_result.json"

cat > /tmp/export_grid.py << 'PYEOF'
import sys
import json
import os

# Add Bonsai libs to path
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/warehouse_grid.ifc"

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
        "n_grids": 0,
        "n_axes": 0,
        "axis_tags": [],
        "u_axes_populated": False,
        "v_axes_populated": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        grids = list(ifc.by_type("IfcGrid"))
        n_grids = len(grids)

        axes = list(ifc.by_type("IfcGridAxis"))
        n_axes = len(axes)
        
        # Collect all tags
        axis_tags = []
        for axis in axes:
            tag = getattr(axis, "AxisTag", None)
            if tag:
                axis_tags.append(str(tag))

        u_populated = False
        v_populated = False
        
        for grid in grids:
            # UAxes and VAxes return tuples of IfcGridAxis objects if populated
            if getattr(grid, "UAxes", None) and len(grid.UAxes) > 0:
                u_populated = True
            if getattr(grid, "VAxes", None) and len(grid.VAxes) > 0:
                v_populated = True

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_grids": n_grids,
            "n_axes": n_axes,
            "axis_tags": axis_tags,
            "u_axes_populated": u_populated,
            "v_axes_populated": v_populated,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_grids": 0,
            "n_axes": 0,
            "axis_tags": [],
            "u_axes_populated": False,
            "v_axes_populated": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run extraction script using Blender's bundled python
/opt/blender/blender --background --python /tmp/export_grid.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback if script produced no output
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_grids":0,"n_axes":0,"axis_tags":[],"u_axes_populated":false,"v_axes_populated":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"