#!/bin/bash
echo "=== Exporting hvac_system_grouping_and_specification result ==="

source /workspace/scripts/task_utils.sh || true

take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/hvac_system_result.json"

cat > /tmp/export_hvac_system.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/hvac_system.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

EMPTY = {
    "file_exists": False, "file_mtime": 0.0, "task_start": task_start,
    "ahu_found": False, "ahu_name": None, "ahu_pset": {},
    "n_duct_segments": 0, "ducts_with_pset": 0,
    "n_air_terminals": 0, "terminals_with_pset": 0,
    "systems": []
}

if not os.path.exists(ifc_path):
    result = EMPTY
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        def get_pset_props(element, pset_name_fragment):
            props = {}
            for inv in ifc.get_inverse(element):
                if inv.is_a("IfcRelDefinesByProperties"):
                    pdef = inv.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet"):
                        if pset_name_fragment.lower() in pdef.Name.lower():
                            for p in (pdef.HasProperties or []):
                                if hasattr(p, "NominalValue") and p.NominalValue:
                                    try:
                                        props[p.Name] = p.NominalValue.wrappedValue
                                    except Exception:
                                        props[p.Name] = str(p.NominalValue)
            return props

        # AHU - IfcUnitaryEquipment
        ahus = list(ifc.by_type("IfcUnitaryEquipment"))
        ahu_found = len(ahus) > 0
        ahu_name = ahus[0].Name if ahu_found else None
        ahu_pset = get_pset_props(ahus[0], "UnitaryEquipment") if ahu_found else {}

        # Duct segments
        ducts = list(ifc.by_type("IfcDuctSegment"))
        ducts_with_pset = sum(1 for d in ducts if get_pset_props(d, "DuctSegment"))

        # Air terminals
        terminals = list(ifc.by_type("IfcAirTerminal"))
        terminals_with_pset = sum(1 for t in terminals if get_pset_props(t, "AirTerminal"))

        # Systems
        systems_data = []
        for sys_obj in ifc.by_type("IfcSystem"):
            members = []
            for inv in ifc.get_inverse(sys_obj):
                if inv.is_a("IfcRelAssignsToGroup") and inv.RelatingGroup == sys_obj:
                    for obj in (inv.RelatedObjects or []):
                        members.append({"name": obj.Name or "", "class": obj.is_a()})
            systems_data.append({
                "name": sys_obj.Name or "",
                "object_type": sys_obj.ObjectType or "",
                "member_count": len(members),
                "members": members
            })

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "ahu_found": ahu_found,
            "ahu_name": ahu_name,
            "ahu_pset": {k: str(v) for k, v in ahu_pset.items()},
            "n_duct_segments": len(ducts),
            "ducts_with_pset": ducts_with_pset,
            "n_air_terminals": len(terminals),
            "terminals_with_pset": terminals_with_pset,
            "systems": systems_data
        }

    except Exception as e:
        result = dict(EMPTY)
        result.update({"file_exists": True, "file_mtime": os.path.getmtime(ifc_path), "error": str(e)})

print("RESULT:" + json.dumps(result, default=str))
PYEOF

/opt/blender/blender --background --python /tmp/export_hvac_system.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"error":"Export produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
