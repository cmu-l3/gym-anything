#!/bin/bash
echo "=== Exporting accessible_ramp_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/ramp_result.json"

cat > /tmp/export_ramp.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_accessible.ifc"

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
        "n_ramps": 0,
        "n_flights": 0,
        "n_railings": 0,
        "has_slope_prop": False,
        "is_contained": False,
        "handrail_type_present": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        import ifcopenshell.util.element
        
        ifc = ifcopenshell.open(ifc_path)
        
        ramps = list(ifc.by_type("IfcRamp"))
        flights = list(ifc.by_type("IfcRampFlight"))
        railings = list(ifc.by_type("IfcRailing"))
        
        has_slope_prop = False
        ramp_elements = ramps + flights
        for el in ramp_elements:
            try:
                psets = ifcopenshell.util.element.get_psets(el)
                for pset_name, props in psets.items():
                    if isinstance(props, dict):
                        for prop_name in props.keys():
                            if "slope" in prop_name.lower() or "gradient" in prop_name.lower():
                                has_slope_prop = True
                                break
                    if has_slope_prop:
                        break
            except Exception:
                pass
            if has_slope_prop:
                break
                
        is_contained = False
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            for obj in (rel.RelatedElements or []):
                if obj.is_a("IfcRamp") or obj.is_a("IfcRampFlight"):
                    is_contained = True
                    break
            if is_contained:
                break
                
        handrail_type_present = False
        for railing in railings:
            if hasattr(railing, "PredefinedType") and railing.PredefinedType == "HANDRAIL":
                handrail_type_present = True
                break
                
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_ramps": len(ramps),
            "n_flights": len(flights),
            "n_railings": len(railings),
            "has_slope_prop": has_slope_prop,
            "is_contained": is_contained,
            "handrail_type_present": handrail_type_present,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_ramps": 0,
            "n_flights": 0,
            "n_railings": 0,
            "has_slope_prop": False,
            "is_contained": False,
            "handrail_type_present": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_ramp.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_ramps":0,"n_flights":0,"n_railings":0,"has_slope_prop":false,"is_contained":false,"handrail_type_present":false,"task_start":0}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"