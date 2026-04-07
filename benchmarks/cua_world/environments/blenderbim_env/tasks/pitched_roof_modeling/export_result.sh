#!/bin/bash
echo "=== Exporting pitched_roof_modeling result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before exporting
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/pitched_roof_result.json"

cat > /tmp/export_pitched_roof.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/pitched_roof_house.ifc"

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
        "project_name": "",
        "n_walls": 0,
        "n_roofs": 0,
        "n_roof_slabs": 0,
        "roof_material_defined": False,
        "roof_material_assigned": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Project name
        projects = ifc.by_type("IfcProject")
        project_name = projects[0].Name if projects else ""

        # 2. Walls
        walls = ifc.by_type("IfcWall")
        n_walls = len(walls)

        # 3. Roofs and Roof Slabs
        roofs = ifc.by_type("IfcRoof")
        n_roofs = len(roofs)
        
        slabs = ifc.by_type("IfcSlab")
        roof_slabs = [s for s in slabs if s.PredefinedType == 'ROOF']
        n_roof_slabs = len(roof_slabs)

        # 4. Material checking
        ROOF_KEYWORDS = ["tile", "slate", "shingle", "clay", "roof"]
        materials = ifc.by_type("IfcMaterial")
        mat_names = [m.Name for m in materials if m.Name]
        
        roof_material_defined = any(
            any(kw in n.lower() for kw in ROOF_KEYWORDS) 
            for n in mat_names
        )

        roof_material_assigned = False
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            mat = rel.RelatingMaterial
            mat_name = ""
            
            if mat.is_a("IfcMaterial"):
                mat_name = mat.Name or ""
            elif mat.is_a("IfcMaterialLayerSetUsage") and mat.ForLayerSet:
                for layer in (mat.ForLayerSet.MaterialLayers or []):
                    if layer.Material and layer.Material.Name:
                        mat_name += layer.Material.Name + " "
            elif mat.is_a("IfcMaterialLayerSet"):
                for layer in (mat.MaterialLayers or []):
                    if layer.Material and layer.Material.Name:
                        mat_name += layer.Material.Name + " "
            
            # If the assigned material name contains one of our keywords
            if any(kw in mat_name.lower() for kw in ROOF_KEYWORDS):
                # Check if it's assigned to any actual objects
                if rel.RelatedObjects and len(rel.RelatedObjects) > 0:
                    roof_material_assigned = True
                    break

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": project_name or "",
            "n_walls": n_walls,
            "n_roofs": n_roofs,
            "n_roof_slabs": n_roof_slabs,
            "material_names": mat_names,
            "roof_material_defined": roof_material_defined,
            "roof_material_assigned": roof_material_assigned,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": "",
            "n_walls": 0,
            "n_roofs": 0,
            "n_roof_slabs": 0,
            "roof_material_defined": False,
            "roof_material_assigned": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run export script using Blender's bundled Python and IfcOpenShell
/opt/blender/blender --background --python /tmp/export_pitched_roof.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback if export produced no output
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"