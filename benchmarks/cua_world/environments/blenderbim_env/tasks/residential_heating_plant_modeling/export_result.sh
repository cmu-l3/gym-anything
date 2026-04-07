#!/bin/bash
echo "=== Exporting residential_heating_plant_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/heating_plant_result.json"

cat > /tmp/export_heating_plant.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_heating_plant.ifc"

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
        "n_boilers": 0,
        "boiler_has_water_type": False,
        "n_tanks": 0,
        "tank_has_storage_type": False,
        "n_pumps": 0,
        "heating_system_exists": False,
        "system_assigned_count": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        # ── 1. Boilers ────────────────────────────────────────────────────────
        boilers = list(ifc.by_type("IfcBoiler"))
        n_boilers = len(boilers)
        boiler_has_water_type = False
        for b in boilers:
            ptype = getattr(b, "PredefinedType", "")
            if ptype and str(ptype).upper() == "WATER":
                boiler_has_water_type = True

        # ── 2. Tanks ──────────────────────────────────────────────────────────
        tanks = list(ifc.by_type("IfcTank"))
        n_tanks = len(tanks)
        tank_has_storage_type = False
        for t in tanks:
            ptype = getattr(t, "PredefinedType", "")
            if ptype and str(ptype).upper() == "STORAGE":
                tank_has_storage_type = True

        # ── 3. Pumps ──────────────────────────────────────────────────────────
        pumps = list(ifc.by_type("IfcPump"))
        n_pumps = len(pumps)

        # ── 4. System Grouping ────────────────────────────────────────────────
        systems = list(ifc.by_type("IfcSystem"))
        heating_systems = [s for s in systems if s.Name and "heating" in str(s.Name).lower()]
        heating_system_exists = len(heating_systems) > 0

        # Check if the equipment is assigned to the heating system
        system_assigned_count = 0
        if heating_system_exists:
            target_system = heating_systems[0]
            assigned_element_ids = set()
            
            # Find all RelAssignsToGroup relationships where RelatingGroup is our system
            for rel in ifc.by_type("IfcRelAssignsToGroup"):
                if getattr(rel, "RelatingGroup", None) == target_system:
                    objects = getattr(rel, "RelatedObjects", [])
                    if objects:
                        for obj in objects:
                            assigned_element_ids.add(obj.id())
            
            # Count how many of our required elements are in this set
            for eq in boilers + tanks + pumps:
                if eq.id() in assigned_element_ids:
                    system_assigned_count += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boilers": n_boilers,
            "boiler_has_water_type": boiler_has_water_type,
            "n_tanks": n_tanks,
            "tank_has_storage_type": tank_has_storage_type,
            "n_pumps": n_pumps,
            "heating_system_exists": heating_system_exists,
            "system_assigned_count": system_assigned_count,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boilers": 0,
            "boiler_has_water_type": False,
            "n_tanks": 0,
            "tank_has_storage_type": False,
            "n_pumps": 0,
            "heating_system_exists": False,
            "system_assigned_count": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_heating_plant.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_boilers":0,"n_tanks":0,"n_pumps":0,"heating_system_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"