#!/bin/bash
echo "=== Exporting construction_site_logistics result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/site_logistics_result.json"

cat > /tmp/export_site_logistics.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_site_logistics.ifc"

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
        "any_transport_element": False,
        "crane_transport_element": False,
        "swing_radius_present": False,
        "site_logistics_group": False,
        "crane_in_group": False,
        "radius_in_group": False,
        "hoarding_in_group": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Transport Elements & Cranes
        transport_elements = ifc.by_type("IfcTransportElement")
        any_transport_element = len(transport_elements) > 0
        
        cranes = []
        for te in transport_elements:
            ptype = getattr(te, "PredefinedType", "")
            if ptype == "CRANE":
                cranes.append(te)
        crane_transport_element = len(cranes) > 0

        # 2. Swing Radius
        products = ifc.by_type("IfcProduct")
        radius_elements = []
        for p in products:
            if p.Name and "swing radius" in p.Name.lower():
                radius_elements.append(p)
        swing_radius_present = len(radius_elements) > 0

        # 3. Logistics Group
        groups = ifc.by_type("IfcGroup")
        logistics_groups = []
        for g in groups:
            if g.Name and "site logistics" in g.Name.lower():
                logistics_groups.append(g)
        site_logistics_group = len(logistics_groups) > 0

        # 4. Group Assignments
        crane_in_group = False
        radius_in_group = False
        hoarding_in_group = 0

        if site_logistics_group:
            target_group = logistics_groups[0]
            
            # Find relationships where this group is the RelatingGroup
            rel_assigns = ifc.by_type("IfcRelAssignsToGroup")
            for rel in rel_assigns:
                if rel.RelatingGroup == target_group:
                    for obj in (rel.RelatedObjects or []):
                        if obj in cranes:
                            crane_in_group = True
                        elif obj in radius_elements:
                            radius_in_group = True
                        else:
                            # Verify it's a physical product and not the entire building/site
                            if obj.is_a("IfcProduct") and not obj.is_a("IfcSpatialStructureElement"):
                                hoarding_in_group += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "any_transport_element": any_transport_element,
            "crane_transport_element": crane_transport_element,
            "swing_radius_present": swing_radius_present,
            "site_logistics_group": site_logistics_group,
            "crane_in_group": crane_in_group,
            "radius_in_group": radius_in_group,
            "hoarding_in_group": hoarding_in_group,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "any_transport_element": False,
            "crane_transport_element": False,
            "swing_radius_present": False,
            "site_logistics_group": False,
            "crane_in_group": False,
            "radius_in_group": False,
            "hoarding_in_group": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_site_logistics.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"