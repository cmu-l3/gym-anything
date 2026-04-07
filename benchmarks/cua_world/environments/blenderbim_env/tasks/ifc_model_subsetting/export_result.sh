#!/bin/bash
echo "=== Exporting ifc_model_subsetting result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/subsetting_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_subsetting.py << 'PYEOF'
import sys
import json
import os

# Add Bonsai libs to path
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_structural_only.ifc"

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
        "n_walls": 0,
        "n_slabs": 0,
        "n_doors": 0,
        "n_windows": 0,
        "n_openings": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Count target elements
        n_walls = len(ifc.by_type("IfcWall"))
        n_slabs = len(ifc.by_type("IfcSlab"))
        n_doors = len(ifc.by_type("IfcDoor"))
        n_windows = len(ifc.by_type("IfcWindow"))
        n_openings = len(ifc.by_type("IfcOpeningElement"))
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": n_walls,
            "n_slabs": n_slabs,
            "n_doors": n_doors,
            "n_windows": n_windows,
            "n_openings": n_openings,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": 0,
            "n_slabs": 0,
            "n_doors": 0,
            "n_windows": 0,
            "n_openings": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_subsetting.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_walls":0,"n_slabs":0,"n_doors":0,"n_windows":0,"n_openings":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"