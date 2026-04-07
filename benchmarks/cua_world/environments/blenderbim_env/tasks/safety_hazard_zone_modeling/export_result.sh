#!/bin/bash
echo "=== Exporting safety_hazard_zone_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/safety_hazard_result.json"

cat > /tmp/export_safety_hazards.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_safety_hazards.ifc"

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
        "n_hazard_elements": 0,
        "hazard_element_names": [],
        "has_pset_risk": False,
        "has_risk_type": False,
        "has_mitigation": False,
        "has_material": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Find Hazard Elements
        hazard_elements = []
        for elem_type in ["IfcSpatialZone", "IfcBuildingElementProxy"]:
            for e in ifc.by_type(elem_type):
                name = (e.Name or "").lower()
                desc = (e.Description or "").lower()
                if "hazard" in name or "risk" in name or "hazard" in desc or "risk" in desc:
                    hazard_elements.append(e)
        
        has_pset_risk = False
        has_risk_type = False
        has_mitigation = False
        has_material = False
        
        # 2. Inspect found elements for Psets and Materials
        for e in hazard_elements:
            # Check properties
            for rel in getattr(e, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pdef = rel.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet") and pdef.Name == "Pset_Risk":
                        has_pset_risk = True
                        for prop in getattr(pdef, "HasProperties", []):
                            if prop.Name == "RiskType": has_risk_type = True
                            if prop.Name == "Mitigation": has_mitigation = True
            
            # Check materials
            for rel in getattr(e, "HasAssociations", []):
                if rel.is_a("IfcRelAssociatesMaterial"):
                    has_material = True

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_hazard_elements": len(hazard_elements),
            "hazard_element_names": [e.Name for e in hazard_elements if e.Name],
            "has_pset_risk": has_pset_risk,
            "has_risk_type": has_risk_type,
            "has_mitigation": has_mitigation,
            "has_material": has_material,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_hazard_elements": 0,
            "hazard_element_names": [],
            "has_pset_risk": False,
            "has_risk_type": False,
            "has_mitigation": False,
            "has_material": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_safety_hazards.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"