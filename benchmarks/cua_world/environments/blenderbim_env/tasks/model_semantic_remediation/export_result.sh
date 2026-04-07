#!/bin/bash
echo "=== Exporting model_semantic_remediation result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/remediation_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_remediation.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_remediated.ifc"

# Read task start timestamp
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
        "task_start": task_start,
        "n_walls": 0, "geom_walls": 0,
        "n_windows": 0, "geom_windows": 0,
        "n_doors": 0, "geom_doors": 0,
        "n_slabs": 0, "geom_slabs": 0,
        "n_proxies": 0
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        def count_valid(entities):
            geom_count = 0
            for e in entities:
                # To combat anti-gaming (spawning empty entities), check for geometry
                if getattr(e, "Representation", None) is not None and getattr(e, "ObjectPlacement", None) is not None:
                    geom_count += 1
            return len(entities), geom_count

        n_walls, geom_walls = count_valid(ifc.by_type("IfcWall"))
        n_windows, geom_windows = count_valid(ifc.by_type("IfcWindow"))
        n_doors, geom_doors = count_valid(ifc.by_type("IfcDoor"))
        n_slabs, geom_slabs = count_valid(ifc.by_type("IfcSlab"))
        n_proxies = len(ifc.by_type("IfcBuildingElementProxy"))

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_walls": n_walls,
            "geom_walls": geom_walls,
            "n_windows": n_windows,
            "geom_windows": geom_windows,
            "n_doors": n_doors,
            "geom_doors": geom_doors,
            "n_slabs": n_slabs,
            "geom_slabs": geom_slabs,
            "n_proxies": n_proxies
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "error": str(e),
            "n_walls": 0, "geom_walls": 0,
            "n_windows": 0, "geom_windows": 0,
            "n_doors": 0, "geom_doors": 0,
            "n_slabs": 0, "geom_slabs": 0,
            "n_proxies": 0
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_remediation.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"