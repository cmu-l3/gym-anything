#!/bin/bash
echo "=== Exporting client_specific_pset_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/custom_pset_result.json"

cat > /tmp/export_custom_pset.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_eir_compliant.ifc"

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
        "pset_found": False,
        "asset_id_type_ok": False,
        "condition_score_type_ok": False,
        "is_maintainable_type_ok": False,
        "target_element_count": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        pset_found = False
        asset_id_type_ok = False
        condition_score_type_ok = False
        is_maintainable_type_ok = False
        target_element_ids = set()

        rels = list(ifc.by_type("IfcRelDefinesByProperties"))
        for rel in rels:
            pdef = rel.RelatingPropertyDefinition
            if pdef and pdef.is_a("IfcPropertySet") and pdef.Name == "Pset_ClientAssetData":
                pset_found = True
                
                if getattr(pdef, "HasProperties", None):
                    for prop in pdef.HasProperties:
                        if prop.is_a("IfcPropertySingleValue"):
                            val = prop.NominalValue
                            if not val:
                                continue
                            
                            if prop.Name == "AssetID":
                                if val.is_a() in ["IfcIdentifier", "IfcLabel", "IfcText"]:
                                    asset_id_type_ok = True
                            elif prop.Name == "ConditionScore":
                                if val.is_a() == "IfcInteger":
                                    condition_score_type_ok = True
                            elif prop.Name == "IsMaintainable":
                                if val.is_a() in ["IfcBoolean", "IfcLogical"]:
                                    is_maintainable_type_ok = True

                if getattr(rel, "RelatedObjects", None):
                    for obj in rel.RelatedObjects:
                        if obj.is_a("IfcDoor") or obj.is_a("IfcWindow"):
                            target_element_ids.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "pset_found": pset_found,
            "asset_id_type_ok": asset_id_type_ok,
            "condition_score_type_ok": condition_score_type_ok,
            "is_maintainable_type_ok": is_maintainable_type_ok,
            "target_element_count": len(target_element_ids),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "pset_found": False,
            "asset_id_type_ok": False,
            "condition_score_type_ok": False,
            "is_maintainable_type_ok": False,
            "target_element_count": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_custom_pset.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"