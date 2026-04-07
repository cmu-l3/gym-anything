#!/bin/bash
echo "=== Exporting geotechnical_stratigraphy_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/geotech_result.json"

cat > /tmp/export_geotech.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_geotech.ifc"

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
        "n_geo_elements": 0,
        "n_valid_geo_elements": 0,
        "n_geo_with_mat": 0,
        "n_geo_with_props": 0,
        "n_geo_below_grade": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        
        ifc = ifcopenshell.open(ifc_path)

        geotech_elements = ifc.by_type("IfcGeographicElement")
        valid_geo_count = 0
        geo_elements_with_mat = 0
        geo_elements_with_props = 0
        geo_elements_below_grade = 0

        material_keywords = ['clay', 'sand', 'gravel', 'rock', 'bedrock', 'soil', 'silt', 'limestone', 'earth']
        prop_keywords = ['bearingcapacity', 'frictionangle', 'soildensity', 'permeability']

        for elem in geotech_elements:
            # 1. Check geometry / representation
            if getattr(elem, "Representation", None):
                valid_geo_count += 1

            # 2. Check geotechnical materials assigned
            has_valid_mat = False
            for rel in getattr(elem, "HasAssociations", []):
                if rel.is_a("IfcRelAssociatesMaterial"):
                    mat_str = str(rel.RelatingMaterial).lower()
                    if any(kw in mat_str for kw in material_keywords):
                        has_valid_mat = True
                        break
            if has_valid_mat:
                geo_elements_with_mat += 1

            # 3. Check specific engineering properties
            has_valid_prop = False
            for rel in getattr(elem, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pdef = rel.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet"):
                        for prop in getattr(pdef, "HasProperties", []):
                            prop_name = getattr(prop, "Name", "").lower()
                            if any(kw in prop_name for kw in prop_keywords):
                                has_valid_prop = True
                                break
                    if has_valid_prop: break
            
            if has_valid_prop:
                geo_elements_with_props += 1

            # 4. Check Z placement (below grade / 1.0m)
            z_val = 0.0
            try:
                placement = elem.ObjectPlacement
                if placement and placement.is_a("IfcLocalPlacement"):
                    rel_placement = placement.RelativePlacement
                    if rel_placement and rel_placement.is_a("IfcAxis2Placement3D"):
                        coords = rel_placement.Location.Coordinates
                        if len(coords) >= 3:
                            z_val = coords[2]
            except Exception:
                pass

            if z_val <= 1.0:
                geo_elements_below_grade += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_geo_elements": len(geotech_elements),
            "n_valid_geo_elements": valid_geo_count,
            "n_geo_with_mat": geo_elements_with_mat,
            "n_geo_with_props": geo_elements_with_props,
            "n_geo_below_grade": geo_elements_below_grade,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_geo_elements": 0,
            "n_valid_geo_elements": 0,
            "n_geo_with_mat": 0,
            "n_geo_with_props": 0,
            "n_geo_below_grade": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_geotech.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_geo_elements":0,"n_valid_geo_elements":0,"n_geo_with_mat":0,"n_geo_with_props":0,"n_geo_below_grade":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"