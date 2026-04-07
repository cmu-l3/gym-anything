#!/bin/bash
echo "=== Exporting mep_equipment_port_definition result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before closing/parsing
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/mep_boiler_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_mep_boiler.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_mep_boiler.ifc"

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
        "n_ports": 0,
        "n_linked_ports": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        boilers = list(ifc.by_type("IfcBoiler"))
        ports = list(ifc.by_type("IfcDistributionPort"))

        # Find linked ports (ports properly nested or connected to a boiler)
        linked_port_ids = set()
        
        # Check standard IFC nesting
        for rel in ifc.by_type("IfcRelNests"):
            if rel.RelatingObject and rel.RelatingObject.is_a("IfcBoiler"):
                for obj in (rel.RelatedObjects or []):
                    if obj.is_a("IfcDistributionPort"):
                        linked_port_ids.add(obj.id())
                        
        # Check alternative IFC port connection method
        for rel in ifc.by_type("IfcRelConnectsPortToElement"):
            if rel.RelatedElement and rel.RelatedElement.is_a("IfcBoiler"):
                if rel.RelatingPort and rel.RelatingPort.is_a("IfcDistributionPort"):
                    linked_port_ids.add(rel.RelatingPort.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boilers": len(boilers),
            "n_ports": len(ports),
            "n_linked_ports": len(linked_port_ids),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boilers": 0,
            "n_ports": 0,
            "n_linked_ports": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_mep_boiler.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_boilers":0,"n_ports":0,"n_linked_ports":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"