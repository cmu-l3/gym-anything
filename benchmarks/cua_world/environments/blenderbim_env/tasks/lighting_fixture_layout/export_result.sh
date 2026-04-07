#!/bin/bash
echo "=== Exporting lighting_fixture_layout result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/lighting_result.json"

cat > /tmp/export_lighting.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_lighting.ifc"

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
        "task_start": task_start,
        "n_fixtures": 0,
        "n_contained": 0,
        "n_with_pset": 0,
        "n_with_lighting_prop": 0
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Count IfcLightFixture entities
        fixtures = list(ifc.by_type("IfcLightFixture"))
        fixture_ids = {f.id() for f in fixtures}
        
        # 2. Check spatial containment
        contained_fixture_ids = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            for obj in (rel.RelatedElements or []):
                if obj.id() in fixture_ids:
                    contained_fixture_ids.add(obj.id())

        # 3. Check property enrichment
        fixtures_with_pset = set()
        fixtures_with_lighting_prop = set()
        
        lighting_keywords = ["wattage", "luminous", "flux", "voltage", "color", "power"]
        
        for f in fixtures:
            has_pset = False
            has_lprop = False
            
            for rel in getattr(f, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pdef = rel.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet"):
                        has_pset = True
                        # Check properties within the Pset
                        for prop in getattr(pdef, "HasProperties", []):
                            prop_name = getattr(prop, "Name", "").lower()
                            if any(kw in prop_name for kw in lighting_keywords):
                                has_lprop = True
                                
            if has_pset:
                fixtures_with_pset.add(f.id())
            if has_lprop:
                fixtures_with_lighting_prop.add(f.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_fixtures": len(fixtures),
            "n_contained": len(contained_fixture_ids),
            "n_with_pset": len(fixtures_with_pset),
            "n_with_lighting_prop": len(fixtures_with_lighting_prop)
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_fixtures": 0,
            "n_contained": 0,
            "n_with_pset": 0,
            "n_with_lighting_prop": 0,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_lighting.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"n_fixtures":0,"n_contained":0,"n_with_pset":0,"n_with_lighting_prop":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"