#!/bin/bash
echo "=== Exporting solar_panel_array_modeling result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before extracting data
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/solar_result.json"

# Write the Python export script to run inside headless Blender
cat > /tmp/export_solar_data.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_solar_retrofit.ifc"

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
        "n_walls": 0,
        "n_solar_devices": 0,
        "system_names": [],
        "n_devices_in_solar_system": 0,
        "power_property_found": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Anti-gaming: check if original walls exist
        walls = ifc.by_type("IfcWall")
        n_walls = len(walls)
        
        # 2. Count IfcSolarDevice
        solar_devices = ifc.by_type("IfcSolarDevice")
        n_solar_devices = len(solar_devices)
        
        # 3. Check Logical Systems
        systems = ifc.by_type("IfcSystem")
        system_names = [s.Name for s in systems if s.Name]
        
        solar_system_entities = []
        for s in systems:
            name = (s.Name or "").lower()
            desc = (s.Description or "").lower()
            obj_type = (s.ObjectType or "").lower()
            if any(k in name or k in desc or k in obj_type for k in ["solar", "pv", "photovoltaic"]):
                solar_system_entities.append(s)
                
        # 4. Check Assignments to the Solar System
        n_devices_in_solar_system = 0
        devices_assigned_to_solar = set()
        
        for rel in ifc.by_type("IfcRelAssignsToGroup"):
            group = rel.RelatingGroup
            if group in solar_system_entities:
                for obj in (rel.RelatedObjects or []):
                    if obj.is_a("IfcSolarDevice"):
                        devices_assigned_to_solar.add(obj.id())
                        
        n_devices_in_solar_system = len(devices_assigned_to_solar)
        
        # 5. Check Properties (Power, Watt, Capacity)
        def has_power_property(element):
            for rel in getattr(element, 'IsDefinedBy', []):
                if rel.is_a('IfcRelDefinesByProperties'):
                    pset = rel.RelatingPropertyDefinition
                    if pset and pset.is_a('IfcPropertySet'):
                        for prop in getattr(pset, 'HasProperties', []):
                            if prop.is_a('IfcPropertySingleValue'):
                                prop_name = (getattr(prop, 'Name', '') or '').lower()
                                if any(k in prop_name for k in ['power', 'watt', 'capacity']):
                                    return True
            return False

        power_property_found = False
        
        # Check properties on the systems
        for s in solar_system_entities:
            if has_power_property(s):
                power_property_found = True
                break
                
        # Check properties on the devices
        if not power_property_found:
            for d in solar_devices:
                if has_power_property(d):
                    power_property_found = True
                    break

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": n_walls,
            "n_solar_devices": n_solar_devices,
            "system_names": system_names,
            "n_devices_in_solar_system": n_devices_in_solar_system,
            "power_property_found": power_property_found,
            "task_start": task_start
        }
        
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": 0,
            "n_solar_devices": 0,
            "system_names": [],
            "n_devices_in_solar_system": 0,
            "power_property_found": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run the python script in headless Blender to leverage the bundled ifcopenshell
/opt/blender/blender --background --python /tmp/export_solar_data.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback in case of absolute failure
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"