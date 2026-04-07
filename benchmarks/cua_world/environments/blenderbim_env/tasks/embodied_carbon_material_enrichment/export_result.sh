#!/bin/bash
echo "=== Exporting embodied_carbon_material_enrichment result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/embodied_carbon_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_embodied_carbon.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_embodied_carbon.ifc"

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
        "concrete_exists": False,
        "timber_exists": False,
        "has_env_pset": False,
        "has_gwp": False,
        "concrete_slab_count": 0,
        "timber_wall_count": 0
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Check if materials exist
        materials = list(ifc.by_type("IfcMaterial"))
        mat_names = [m.Name for m in materials if m.Name]
        
        concrete_exists = any("concrete" in n.lower() for n in mat_names)
        timber_exists = any("timber" in n.lower() for n in mat_names)

        # 2. Check for environmental property sets
        # IFC4 standard uses IfcExtendedMaterialProperties for material Psets
        env_psets = [p for p in ifc.by_type("IfcExtendedMaterialProperties") if getattr(p, "Name", "") == "Pset_EnvironmentalImpactIndicators"]
        # Fallback if agent applied it directly to elements or as standard Pset
        env_psets += [p for p in ifc.by_type("IfcPropertySet") if getattr(p, "Name", "") == "Pset_EnvironmentalImpactIndicators"]
        
        has_env_pset = len(env_psets) > 0
        
        has_gwp = False
        for pset in env_psets:
            props = getattr(pset, "Properties", getattr(pset, "HasProperties", []))
            for prop in props:
                if getattr(prop, "Name", "") == "GlobalWarmingPotential":
                    has_gwp = True
                    break

        # 3. Check Material Assignments
        concrete_slabs = set()
        timber_walls = set()

        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            mat = getattr(rel, "RelatingMaterial", None)
            if not mat: continue
            
            # Use string representation to catch nested material sets
            mat_str = str(mat).lower()
            is_concrete = "concrete" in mat_str
            is_timber = "timber" in mat_str
            
            for obj in getattr(rel, "RelatedObjects", []):
                if is_concrete and obj.is_a("IfcSlab"):
                    concrete_slabs.add(obj.id())
                if is_timber and obj.is_a("IfcWall"):
                    timber_walls.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "concrete_exists": concrete_exists,
            "timber_exists": timber_exists,
            "has_env_pset": has_env_pset,
            "has_gwp": has_gwp,
            "concrete_slab_count": len(concrete_slabs),
            "timber_wall_count": len(timber_walls)
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "error": str(e),
            "concrete_exists": False,
            "timber_exists": False,
            "has_env_pset": False,
            "has_gwp": False,
            "concrete_slab_count": 0,
            "timber_wall_count": 0
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_embodied_carbon.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"