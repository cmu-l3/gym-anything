#!/bin/bash
echo "=== Exporting security_system_modeling result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/security_result.json"

# Python script to run headlessly and extract IFC contents
cat > /tmp/export_security.py << 'PYEOF'
import sys
import json
import os

# Ensure ifcopenshell can be imported from BlenderBIM's bundled libs
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_security.ifc"

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
        "n_security_appliances": 0,
        "n_av_appliances": 0,
        "n_alarms": 0,
        "security_system_present": False,
        "n_elements_assigned_to_system": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Count individual security element types
        security_appliances = list(ifc.by_type("IfcSecurityAppliance"))
        av_appliances = list(ifc.by_type("IfcAudioVisualAppliance"))
        alarms = list(ifc.by_type("IfcAlarm"))

        # Look for the distribution system
        dist_systems = list(ifc.by_type("IfcDistributionSystem"))
        security_system = None
        for sys in dist_systems:
            name = (sys.Name or "").lower()
            if "security" in name or "access" in name:
                security_system = sys
                break

        # Check grouped elements if the system exists
        n_assigned = 0
        if security_system:
            for rel in ifc.by_type("IfcRelAssignsToGroup"):
                if rel.RelatingGroup == security_system:
                    for obj in (rel.RelatedObjects or []):
                        if obj.is_a("IfcSecurityAppliance") or obj.is_a("IfcAudioVisualAppliance") or obj.is_a("IfcAlarm"):
                            n_assigned += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_security_appliances": len(security_appliances),
            "n_av_appliances": len(av_appliances),
            "n_alarms": len(alarms),
            "security_system_present": (security_system is not None),
            "system_name": security_system.Name if security_system else "",
            "n_elements_assigned_to_system": n_assigned,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_security_appliances": 0,
            "n_av_appliances": 0,
            "n_alarms": 0,
            "security_system_present": False,
            "n_elements_assigned_to_system": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run via Blender's Python
/opt/blender/blender --background --python /tmp/export_security.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output from export script"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"