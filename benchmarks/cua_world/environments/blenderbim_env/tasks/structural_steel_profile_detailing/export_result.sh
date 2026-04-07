#!/bin/bash
echo "=== Exporting structural_steel_profile_detailing result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/steel_profile_result.json"

cat > /tmp/export_steel_profile.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/steel_portal_frame.ifc"

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
        "n_ishapes": 0,
        "n_profile_sets": 0,
        "members_with_profile": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Count IfcIShapeProfileDef
        ishapes = ifc.by_type("IfcIShapeProfileDef")
        n_ishapes = len(ishapes)

        # Count IfcMaterialProfileSet
        profile_sets = ifc.by_type("IfcMaterialProfileSet")
        n_profile_sets = len(profile_sets)

        # Traverse material associations to count how many members use the I-Shape
        members_with_profile = 0
        structural_elements = ifc.by_type("IfcColumn") + ifc.by_type("IfcBeam")

        for elem in structural_elements:
            has_profile = False
            for rel in getattr(elem, "HasAssociations", []):
                if rel.is_a("IfcRelAssociatesMaterial"):
                    mat = rel.RelatingMaterial
                    if mat:
                        if mat.is_a("IfcMaterialProfileSetUsage"):
                            pset = mat.ForProfileSet
                            if pset:
                                for mp in getattr(pset, "MaterialProfiles", []):
                                    if mp.Profile and mp.Profile.is_a("IfcIShapeProfileDef"):
                                        has_profile = True
                        elif mat.is_a("IfcMaterialProfileSet"):
                            for mp in getattr(mat, "MaterialProfiles", []):
                                if mp.Profile and mp.Profile.is_a("IfcIShapeProfileDef"):
                                    has_profile = True
            if has_profile:
                members_with_profile += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_ishapes": n_ishapes,
            "n_profile_sets": n_profile_sets,
            "members_with_profile": members_with_profile,
            "total_structural_elements": len(structural_elements),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_ishapes": 0,
            "n_profile_sets": 0,
            "members_with_profile": 0,
            "total_structural_elements": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_steel_profile.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_ishapes":0,"n_profile_sets":0,"members_with_profile":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"