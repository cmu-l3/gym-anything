#!/bin/bash
echo "=== Exporting security_system_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/security_result.json"

cat > /tmp/export_security.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_security_system.ifc"

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
        "n_sec_apps": 0,
        "n_cameras": 0,
        "n_valid_systems": 0,
        "n_assigned_targets": 0,
        "total_targets": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Count Security Appliances
        sec_apps = list(ifc.by_type("IfcSecurityAppliance"))
        
        # 2. Count Cameras (Communications or Sensor)
        comm_apps = list(ifc.by_type("IfcCommunicationsAppliance"))
        sensors = list(ifc.by_type("IfcSensor"))
        cameras = comm_apps + sensors

        # 3. Find valid Security Distribution Systems
        dist_systems = list(ifc.by_type("IfcDistributionSystem"))
        valid_systems = []
        for s in dist_systems:
            name = (s.Name or "") + " " + (s.LongName or "")
            if "secur" in name.lower() or "surveill" in name.lower():
                valid_systems.append(s)

        # 4. Check Group Assignments
        assigned_objects = set()
        for sys_obj in valid_systems:
            # IfcGroup uses IsGroupedBy inverse relationship to IfcRelAssignsToGroup
            for rel in getattr(sys_obj, "IsGroupedBy", []):
                if rel.is_a("IfcRelAssignsToGroup"):
                    for obj in (rel.RelatedObjects or []):
                        assigned_objects.add(obj.id())

        target_devices = sec_apps + cameras
        assigned_target_count = sum(1 for d in target_devices if d.id() in assigned_objects)

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_sec_apps": len(sec_apps),
            "n_cameras": len(cameras),
            "n_valid_systems": len(valid_systems),
            "n_assigned_targets": assigned_target_count,
            "total_targets": len(target_devices),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_sec_apps": 0,
            "n_cameras": 0,
            "n_valid_systems": 0,
            "n_assigned_targets": 0,
            "total_targets": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_security.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_sec_apps":0,"n_cameras":0,"n_valid_systems":0,"n_assigned_targets":0,"total_targets":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"