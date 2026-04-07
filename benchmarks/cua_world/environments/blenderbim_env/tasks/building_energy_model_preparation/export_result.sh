#!/bin/bash
echo "=== Exporting building_energy_model_preparation result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/energy_model_result.json"

# Write Python script to parse the output IFC file using ifcopenshell
cat > /tmp/export_energy_model.py << 'PYEOF'
import sys
import json
import os

# Ensure Bonsai's bundled ifcopenshell is in the path
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_energy_model.ifc"

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
        "n_space_boundaries": 0,
        "n_spaces_with_pset": 0,
        "has_thermal_property_populated": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Count Space Boundaries
        boundaries = ifc.by_type("IfcRelSpaceBoundary")
        n_boundaries = len(boundaries)

        # 2. Inspect Spaces for Thermal Design Psets and Properties
        spaces = ifc.by_type("IfcSpace")
        spaces_with_pset = 0
        has_thermal_property = False

        for space in spaces:
            has_specific_pset = False
            for rel in getattr(space, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pset = rel.RelatingPropertyDefinition
                    if pset and pset.is_a("IfcPropertySet") and pset.Name == "Pset_SpaceThermalDesign":
                        has_specific_pset = True
                        # Check properties within the Pset
                        for prop in getattr(pset, "HasProperties", []):
                            prop_name = (getattr(prop, "Name", "") or "").lower()
                            # Accept common temperature setpoint names
                            if any(k in prop_name for k in ["heating", "cooling", "temp", "bulb"]):
                                has_thermal_property = True
            
            if has_specific_pset:
                spaces_with_pset += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_space_boundaries": n_boundaries,
            "n_spaces_with_pset": spaces_with_pset,
            "has_thermal_property_populated": has_thermal_property,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_space_boundaries": 0,
            "n_spaces_with_pset": 0,
            "has_thermal_property_populated": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run the python script using blender's bundled python
/opt/blender/blender --background --python /tmp/export_energy_model.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback if execution failed
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_space_boundaries":0,"n_spaces_with_pset":0,"has_thermal_property_populated":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"