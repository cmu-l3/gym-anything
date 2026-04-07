#!/bin/bash
echo "=== Exporting door_type_instantiation result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/door_type_result.json"

cat > /tmp/export_door_type.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_typed_doors.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

result = {
    "file_exists": False,
    "file_mtime": 0.0,
    "task_start": task_start,
    "type_found": False,
    "type_name": "",
    "pset_found": False,
    "manufacturer_value": "",
    "assigned_doors_count": 0
}

if os.path.exists(ifc_path):
    result["file_exists"] = True
    result["file_mtime"] = os.path.getmtime(ifc_path)
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Look for the requested IfcDoorType
        door_types = list(ifc.by_type("IfcDoorType"))
        target_type = None
        for dt in door_types:
            name = (dt.Name or "").lower()
            obj_type = (dt.ObjectType or "").lower()
            if "sd-01" in name or "sd-01" in obj_type:
                target_type = dt
                break
                
        if target_type:
            result["type_found"] = True
            result["type_name"] = target_type.Name or target_type.ObjectType or "SD-01"
            
            # 2. Check property sets attached to the TYPE
            psets = []
            if hasattr(target_type, "HasPropertySets") and target_type.HasPropertySets:
                psets.extend(target_type.HasPropertySets)
            
            # Alternatively, handle IfcRelDefinesByProperties if applicable
            for rel in getattr(target_type, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    prop_def = rel.RelatingPropertyDefinition
                    if prop_def and prop_def.is_a("IfcPropertySet"):
                        psets.append(prop_def)
                        
            for pset in psets:
                if "pset_manufacturertypeinformation" in (pset.Name or "").lower():
                    result["pset_found"] = True
                    for prop in getattr(pset, "HasProperties", []):
                        if (prop.Name or "").lower() == "manufacturer":
                            val = getattr(prop, "NominalValue", None)
                            if val:
                                result["manufacturer_value"] = val.wrappedValue
                            break
                    break
                    
            # 3. Check for IfcDoor instances assigned to this type
            assigned_count = 0
            for rel in ifc.by_type("IfcRelDefinesByType"):
                if rel.RelatingType == target_type:
                    for obj in getattr(rel, "RelatedObjects", []):
                        if obj.is_a("IfcDoor"):
                            assigned_count += 1
            result["assigned_doors_count"] = assigned_count
            
    except Exception as e:
        result["error"] = str(e)

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_door_type.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"