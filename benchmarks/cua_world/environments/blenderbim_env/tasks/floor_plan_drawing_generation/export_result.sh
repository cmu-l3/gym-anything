#!/bin/bash
echo "=== Exporting floor_plan_drawing_generation result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/drawing_result.json"
IFC_PATH="/home/ga/BIMProjects/fzk_with_drawings.ifc"

# Find latest SVG in BIMProjects (Bonsai nests drawings based on project and sheet names)
LATEST_SVG=$(find /home/ga/BIMProjects -name "*.svg" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
SVG_EXISTS="false"
if [ -n "$LATEST_SVG" ]; then
    cp "$LATEST_SVG" /tmp/floor_plan_output.svg
    chmod 644 /tmp/floor_plan_output.svg
    SVG_EXISTS="true"
    echo "Found SVG output at: $LATEST_SVG"
else
    echo "No SVG files found in /home/ga/BIMProjects"
fi

# Query the IFC file to check drawing definitions (IfcAnnotation entities)
cat > /tmp/export_drawing_meta.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_with_drawings.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

svg_exists = sys.argv[1].lower() == "true" if len(sys.argv) > 1 else False

if not os.path.exists(ifc_path):
    result = {
        "ifc_exists": False,
        "ifc_mtime": 0.0,
        "n_annotations": 0,
        "svg_exists": svg_exists,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Drawings boundaries/cameras are stored as IfcAnnotation
        annotations = ifc.by_type("IfcAnnotation")
        
        result = {
            "ifc_exists": True,
            "ifc_mtime": os.path.getmtime(ifc_path),
            "n_annotations": len(annotations),
            "svg_exists": svg_exists,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "ifc_exists": True,
            "ifc_mtime": os.path.getmtime(ifc_path),
            "n_annotations": 0,
            "svg_exists": svg_exists,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_drawing_meta.py -- "$SVG_EXISTS" 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"ifc_exists":false,"svg_exists":'$SVG_EXISTS',"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"