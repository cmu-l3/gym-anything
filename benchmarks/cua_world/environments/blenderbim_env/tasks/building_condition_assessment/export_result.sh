#!/bin/bash
echo "=== Exporting building_condition_assessment result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/condition_assessment_result.json"

cat > /tmp/export_condition_assessment.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_condition_assessment.ifc"

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
        "group_found": False,
        "walls_assigned": 0,
        "slabs_assigned": 0,
        "elements_with_pset": 0,
        "elements_with_poor_condition": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Look for the Defect Remediation group
        groups = ifc.by_type("IfcGroup")
        target_group = None
        for g in groups:
            if g.Name and "defect remediation" in g.Name.lower():
                target_group = g
                break
                
        group_found = target_group is not None
        assigned_elements = []
        
        # 2. Get assigned elements if group exists
        if group_found:
            for rel in getattr(target_group, "IsGroupedBy", []):
                if rel.is_a("IfcRelAssignsToGroup"):
                    for obj in getattr(rel, "RelatedObjects", []):
                        assigned_elements.append(obj)
                        
        walls_assigned = sum(1 for e in assigned_elements if e.is_a("IfcWall"))
        slabs_assigned = sum(1 for e in assigned_elements if e.is_a("IfcSlab"))
        
        # 3. Check for property sets on the assigned elements
        elements_with_pset = 0
        elements_with_poor_condition = 0
        
        for elem in assigned_elements:
            has_pset = False
            has_poor_condition = False
            
            for rel in getattr(elem, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pset = rel.RelatingPropertyDefinition
                    if pset and pset.is_a("IfcPropertySet") and pset.Name == "Pset_Condition":
                        has_pset = True
                        for prop in getattr(pset, "HasProperties", []):
                            if prop.Name == "AssessmentCondition" and getattr(prop, "NominalValue", None):
                                val = prop.NominalValue.wrappedValue
                                if isinstance(val, str) and "poor" in val.lower():
                                    has_poor_condition = True
            
            if has_pset:
                elements_with_pset += 1
            if has_poor_condition:
                elements_with_poor_condition += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "group_found": group_found,
            "walls_assigned": walls_assigned,
            "slabs_assigned": slabs_assigned,
            "elements_with_pset": elements_with_pset,
            "elements_with_poor_condition": elements_with_poor_condition,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "group_found": False,
            "walls_assigned": 0,
            "slabs_assigned": 0,
            "elements_with_pset": 0,
            "elements_with_poor_condition": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_condition_assessment.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"