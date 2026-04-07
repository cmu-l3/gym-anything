#!/bin/bash
echo "=== Exporting material_layer_set_definition result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/material_layers_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_material_layers.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_envelope_spec.ifc"

# Read task start timestamp
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
        "n_layer_sets": 0,
        "layer_set_names": [],
        "n_layers_valid_thickness": 0,
        "n_distinct_materials": 0,
        "elements_with_layer_sets": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Count Material Layer Sets
        layer_sets = list(ifc.by_type("IfcMaterialLayerSet"))
        layer_set_names = [ls.MaterialSetName for ls in layer_sets if getattr(ls, "MaterialSetName", None)]
        
        # 2. Count Material Layers with thickness > 0
        layers = list(ifc.by_type("IfcMaterialLayer"))
        valid_thickness_count = 0
        for l in layers:
            try:
                if float(l.LayerThickness or 0.0) > 0:
                    valid_thickness_count += 1
            except Exception:
                pass
                
        # 3. Count Distinct Materials
        materials = list(ifc.by_type("IfcMaterial"))
        mat_names = list(set([m.Name for m in materials if getattr(m, "Name", None)]))
        
        # 4. Count Elements Associated with Layer Sets
        layer_set_element_ids = set()
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            mat = rel.RelatingMaterial
            if not mat: 
                continue
                
            is_layer_set = False
            if mat.is_a("IfcMaterialLayerSet") or mat.is_a("IfcMaterialLayerSetUsage"):
                is_layer_set = True
                
            if is_layer_set:
                for obj in (rel.RelatedObjects or []):
                    layer_set_element_ids.add(obj.id())
                    
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_layer_sets": len(layer_sets),
            "layer_set_names": layer_set_names,
            "n_layers_valid_thickness": valid_thickness_count,
            "n_distinct_materials": len(mat_names),
            "distinct_material_names": mat_names,
            "elements_with_layer_sets": len(layer_set_element_ids),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_layer_sets": 0,
            "layer_set_names": [],
            "n_layers_valid_thickness": 0,
            "n_distinct_materials": 0,
            "elements_with_layer_sets": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_material_layers.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_layer_sets":0,"n_layers_valid_thickness":0,"n_distinct_materials":0,"elements_with_layer_sets":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"