#!/bin/bash
echo "=== Exporting foundation_footing_layout result ==="

# Capture final state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_screenshot.png 2>/dev/null || true

RESULT_FILE="/tmp/foundation_result.json"

# Write the Python parsing script for Blender/IfcOpenShell
cat > /tmp/export_foundation.py << 'PYEOF'
import sys
import json
import os

# Append Bonsai's internal library path so ifcopenshell can be imported
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/foundation_layout.ifc"

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
        "n_storeys": 0,
        "storey_elevations": [],
        "n_footings": 0,
        "concrete_material_defined": False,
        "concrete_material_assigned_to_footing": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Project name
        projects = ifc.by_type("IfcProject")
        project_name = projects[0].Name if projects and projects[0].Name else ""

        # 2. Storeys & Elevations
        storeys = ifc.by_type("IfcBuildingStorey")
        elevations = []
        for s in storeys:
            try:
                if s.Elevation is not None:
                    elevations.append(float(s.Elevation))
            except Exception:
                pass
        
        # 3. Footings
        footings = ifc.by_type("IfcFooting")
        footing_ids = {f.id() for f in footings}

        # 4. Materials
        materials = ifc.by_type("IfcMaterial")
        concrete_defined = any(
            "concrete" in (m.Name or "").lower() for m in materials
        )

        # 5. Assignments
        mat_rels = ifc.by_type("IfcRelAssociatesMaterial")
        concrete_assigned = False
        
        for rel in mat_rels:
            related_ids = {o.id() for o in (rel.RelatedObjects or [])}
            # Check if this material relation targets any of our footings
            if related_ids & footing_ids:
                # Resolve the material name robustly
                mat = rel.RelatingMaterial
                mat_str = str(mat).lower()
                
                # Check directly in the IFC string representation (handles layered materials)
                if "concrete" in mat_str:
                    concrete_assigned = True
                    break

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": project_name,
            "n_storeys": len(storeys),
            "storey_elevations": sorted(elevations),
            "n_footings": len(footings),
            "concrete_material_defined": concrete_defined,
            "concrete_material_assigned_to_footing": concrete_assigned,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": "",
            "n_storeys": 0,
            "storey_elevations": [],
            "n_footings": 0,
            "concrete_material_defined": False,
            "concrete_material_assigned_to_footing": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run the python script using Blender's Python environment
/opt/blender/blender --background --python /tmp/export_foundation.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback in case of a crash
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output from export script"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"