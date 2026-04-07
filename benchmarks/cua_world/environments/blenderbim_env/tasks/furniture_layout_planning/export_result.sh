#!/bin/bash
echo "=== Exporting furniture_layout_planning result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/furniture_layout_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_furniture.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_furnished.ifc"

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
        "n_furniture": 0,
        "n_furniture_types": 0,
        "type_names": [],
        "n_furniture_with_material": 0,
        "n_furniture_contained": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Furniture count
        furniture = list(ifc.by_type("IfcFurniture"))
        furn_ids = {f.id() for f in furniture}
        
        # 2. Furniture types
        furniture_types = list(ifc.by_type("IfcFurnitureType"))
        type_names = list({t.Name for t in furniture_types if t.Name})
        
        # 3. Material associations
        mat_rels = list(ifc.by_type("IfcRelAssociatesMaterial"))
        furn_with_mat = set()
        for rel in mat_rels:
            for obj in getattr(rel, "RelatedObjects", []):
                if obj.id() in furn_ids:
                    furn_with_mat.add(obj.id())
                    
        # 4. Spatial containment
        cont_rels = list(ifc.by_type("IfcRelContainedInSpatialStructure"))
        furn_contained = set()
        for rel in cont_rels:
            for obj in getattr(rel, "RelatedElements", []):
                if obj.id() in furn_ids:
                    furn_contained.add(obj.id())
                    
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_furniture": len(furniture),
            "n_furniture_types": len(type_names),
            "type_names": type_names,
            "n_furniture_with_material": len(furn_with_mat),
            "n_furniture_contained": len(furn_contained),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_furniture": 0,
            "n_furniture_types": 0,
            "type_names": [],
            "n_furniture_with_material": 0,
            "n_furniture_contained": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_furniture.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_furniture":0,"n_furniture_types":0,"n_furniture_with_material":0,"n_furniture_contained":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"