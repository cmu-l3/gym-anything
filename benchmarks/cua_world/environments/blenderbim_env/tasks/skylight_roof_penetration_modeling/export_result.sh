#!/bin/bash
echo "=== Exporting skylight_roof_penetration_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/skylight_result.json"

# Write a Python script to parse the output IFC and verify topological relationships
cat > /tmp/export_skylight.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_skylight.ifc"

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
        "n_openings": 0,
        "opening_voids_slab": False,
        "window_fills_opening": False,
        "skylight_types_found": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        openings = ifc.by_type("IfcOpeningElement")
        windows = ifc.by_type("IfcWindow")
        fills_rels = ifc.by_type("IfcRelFillsElement")
        voids_rels = ifc.by_type("IfcRelVoidsElement")

        n_openings = len(openings)
        skylight_types_found = sum(1 for w in windows if w.PredefinedType == 'SKYLIGHT')
        
        opening_voids_slab = False
        window_fills_opening = False

        # Traverse topology: look for any opening that voids a Slab/Roof
        for v_rel in voids_rels:
            host = v_rel.RelatingBuildingElement
            opening = v_rel.RelatedOpeningElement

            if host and host.is_a() in ["IfcSlab", "IfcRoof"]:
                opening_voids_slab = True

                # If we found an opening in a slab, check if a window fills it
                for f_rel in fills_rels:
                    if f_rel.RelatingOpeningElement == opening:
                        elem = f_rel.RelatedBuildingElement
                        if elem and elem.is_a("IfcWindow"):
                            window_fills_opening = True

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_openings": n_openings,
            "opening_voids_slab": opening_voids_slab,
            "window_fills_opening": window_fills_opening,
            "skylight_types_found": skylight_types_found,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_openings": 0,
            "opening_voids_slab": False,
            "window_fills_opening": False,
            "skylight_types_found": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_skylight.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"