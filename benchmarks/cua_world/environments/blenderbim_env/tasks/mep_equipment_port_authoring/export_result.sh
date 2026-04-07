#!/bin/bash
echo "=== Exporting mep_equipment_port_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/chiller_result.json"

cat > /tmp/export_mep_authoring.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/arcticflow_chiller.ifc"

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
        "n_equipment": 0,
        "n_ports": 0,
        "n_nested_ports": 0,
        "has_manufacturer_pset": False,
        "manufacturer_name": "",
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        # 1. Find Equipment (IfcChiller or IfcEnergyConversionDevice)
        equipment_elements = list(ifc.by_type("IfcChiller")) + list(ifc.by_type("IfcEnergyConversionDevice"))
        n_equipment = len(equipment_elements)

        # 2. Find Ports
        ports = list(ifc.by_type("IfcDistributionPort")) + list(ifc.by_type("IfcPort"))
        n_ports = len(ports)

        # 3. Check Nested Ports (IfcRelNests)
        n_nested_ports = 0
        equipment_ids = {eq.id() for eq in equipment_elements}
        
        for rel in ifc.by_type("IfcRelNests"):
            if rel.RelatingObject and rel.RelatingObject.id() in equipment_ids:
                for obj in (rel.RelatedObjects or []):
                    if obj.is_a("IfcDistributionPort") or obj.is_a("IfcPort"):
                        n_nested_ports += 1

        # 4. Check Manufacturer Pset
        has_manufacturer_pset = False
        manufacturer_name = ""
        
        for eq in equipment_elements:
            for rel in getattr(eq, 'IsDefinedBy', []):
                if not rel or not rel.is_a("IfcRelDefinesByProperties"):
                    continue
                pset = rel.RelatingPropertyDefinition
                if pset and pset.is_a("IfcPropertySet") and pset.Name == "Pset_ManufacturerTypeInformation":
                    for prop in getattr(pset, 'HasProperties', []):
                        if prop and prop.Name == "Manufacturer" and getattr(prop, 'NominalValue', None):
                            val = str(prop.NominalValue.wrappedValue)
                            if "ArcticFlow" in val:
                                has_manufacturer_pset = True
                                manufacturer_name = val

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_equipment": n_equipment,
            "n_ports": n_ports,
            "n_nested_ports": n_nested_ports,
            "has_manufacturer_pset": has_manufacturer_pset,
            "manufacturer_name": manufacturer_name,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_equipment": 0,
            "n_ports": 0,
            "n_nested_ports": 0,
            "has_manufacturer_pset": False,
            "manufacturer_name": "",
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_mep_authoring.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_equipment":0,"n_ports":0,"n_nested_ports":0,"has_manufacturer_pset":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"