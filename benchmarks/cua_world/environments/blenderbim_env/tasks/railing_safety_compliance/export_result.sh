#!/bin/bash
echo "=== Exporting railing_safety_compliance result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/railing_result.json"

cat > /tmp/export_railings.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_railing_compliant.ifc"

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
        "n_railings": 0,
        "has_predefined_type": False,
        "has_height_property": False,
        "has_metal_material": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        import ifcopenshell.util.element
        
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Count railings
        railings = list(ifc.by_type("IfcRailing"))
        
        # 2. Check PredefinedType
        has_predefined_type = False
        for r in railings:
            pt = getattr(r, "PredefinedType", None)
            if pt in ("GUARDRAIL", "HANDRAIL"):
                has_predefined_type = True
                break
                
        # 3. Check Height property
        has_height_property = False
        for r in railings:
            psets = ifcopenshell.util.element.get_psets(r)
            for pset_name, props in psets.items():
                if 'Height' in props:
                    has_height_property = True
                    break
            if has_height_property:
                break
                
        # 4. Check Material associations
        has_metal_material = False
        railing_ids = {r.id() for r in railings}
        
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            mat = rel.RelatingMaterial
            if not mat:
                continue
                
            mat_name = ""
            if hasattr(mat, "Name") and mat.Name:
                mat_name = mat.Name.lower()
            elif hasattr(mat, "ForLayerSet"):
                pass  # Ignore LayerSet details for now, usually it's direct assignment for railings
                
            related_ids = {o.id() for o in getattr(rel, "RelatedObjects", [])}
            
            # If this material is associated with any of our railings
            if related_ids & railing_ids:
                if any(kw in mat_name for kw in ("steel", "metal", "aluminium", "aluminum")):
                    has_metal_material = True
                    break

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_railings": len(railings),
            "has_predefined_type": has_predefined_type,
            "has_height_property": has_height_property,
            "has_metal_material": has_metal_material,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_railings": 0,
            "has_predefined_type": False,
            "has_height_property": False,
            "has_metal_material": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_railings.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_railings":0,"has_predefined_type":false,"has_height_property":false,"has_metal_material":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"