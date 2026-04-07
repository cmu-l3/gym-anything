#!/bin/bash
echo "=== Exporting interior_covering_specification result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/covering_result.json"

cat > /tmp/export_coverings.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_interior_finishes.ifc"

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
        "n_ceilings": 0,
        "n_floorings": 0,
        "n_coverings_total": 0,
        "has_ceiling_material": False,
        "has_floor_material": False,
        "n_coverings_with_material": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        # 1. Count Coverings
        coverings = list(ifc.by_type("IfcCovering"))
        
        n_ceilings = sum(1 for c in coverings if getattr(c, "PredefinedType", None) == "CEILING")
        n_floorings = sum(1 for c in coverings if getattr(c, "PredefinedType", None) == "FLOORING")
        
        # 2. Check Materials
        materials = list(ifc.by_type("IfcMaterial"))
        material_names = [m.Name for m in materials if m.Name]
        
        ceiling_mat_kws = ["gypsum", "plasterboard"]
        floor_mat_kws = ["oak", "timber", "hardwood", "parquet"]
        
        has_ceiling_mat = any(any(kw in m.lower() for kw in ceiling_mat_kws) for m in material_names)
        has_floor_mat = any(any(kw in m.lower() for kw in floor_mat_kws) for m in material_names)
        
        # 3. Check Material Associations for Coverings
        coverings_with_mat = set()
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            for obj in (rel.RelatedObjects or []):
                if obj.is_a("IfcCovering"):
                    coverings_with_mat.add(obj.id())
                    
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_ceilings": n_ceilings,
            "n_floorings": n_floorings,
            "n_coverings_total": len(coverings),
            "has_ceiling_material": has_ceiling_mat,
            "has_floor_material": has_floor_mat,
            "n_coverings_with_material": len(coverings_with_mat),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_ceilings": 0,
            "n_floorings": 0,
            "n_coverings_total": 0,
            "has_ceiling_material": False,
            "has_floor_material": False,
            "n_coverings_with_material": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_coverings.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_ceilings":0,"n_floorings":0,"has_ceiling_material":false,"has_floor_material":false,"n_coverings_with_material":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"