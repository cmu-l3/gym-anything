#!/bin/bash
echo "=== Exporting structural_reinforcement_detailing result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/reinforcement_result.json"

cat > /tmp/export_reinforcement.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/column_reinforcement.ifc"

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
        "n_columns": 0,
        "n_rebars": 0,
        "concrete_defined": False,
        "steel_defined": False,
        "col_has_concrete": False,
        "rebar_has_steel": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Count specific structural elements
        columns = list(ifc.by_type("IfcColumn"))
        rebars = list(ifc.by_type("IfcReinforcingBar"))
        
        n_columns = len(columns)
        n_rebars = len(rebars)

        # Check for existence of materials by name globally
        concrete_defined = False
        steel_defined = False
        
        for m in ifc.by_type("IfcMaterial"):
            name = (m.Name or "").lower()
            if "concrete" in name:
                concrete_defined = True
            if "steel" in name or "rebar" in name:
                steel_defined = True

        # Check material assignment logic
        col_has_concrete = False
        rebar_has_steel = False

        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            mat = rel.RelatingMaterial
            if not mat:
                continue
            
            # Stringify material to easily check its underlying name 
            # (handles IfcMaterial, IfcMaterialLayerSet, IfcMaterialConstituentSet, etc.)
            mat_str = str(mat).lower()
            
            is_concrete = "concrete" in mat_str
            is_steel = "steel" in mat_str or "rebar" in mat_str

            for obj in (rel.RelatedObjects or []):
                if obj.is_a("IfcColumn") and is_concrete:
                    col_has_concrete = True
                if obj.is_a("IfcReinforcingBar") and is_steel:
                    rebar_has_steel = True

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_columns": n_columns,
            "n_rebars": n_rebars,
            "concrete_defined": concrete_defined,
            "steel_defined": steel_defined,
            "col_has_concrete": col_has_concrete,
            "rebar_has_steel": rebar_has_steel,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_columns": 0,
            "n_rebars": 0,
            "concrete_defined": False,
            "steel_defined": False,
            "col_has_concrete": False,
            "rebar_has_steel": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_reinforcement.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_columns":0,"n_rebars":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"