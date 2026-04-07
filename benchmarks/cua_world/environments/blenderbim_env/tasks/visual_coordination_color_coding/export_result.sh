#!/bin/bash
echo "=== Exporting visual_coordination_color_coding result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/color_coding_result.json"

cat > /tmp/export_color_coding.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_color_coded.ifc"

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
        "has_audit_blue": False,
        "has_blue_style": False,
        "assigned_walls_count": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Check if Audit_Blue material exists
        materials = list(ifc.by_type("IfcMaterial"))
        has_audit_blue = any(m.Name == "Audit_Blue" for m in materials if m.Name)

        # 2. Check if a blue surface style exists (Blue > Red AND Blue > Green)
        colors = list(ifc.by_type("IfcColourRgb"))
        has_blue_style = False
        for c in colors:
            try:
                r = float(c.Red)
                g = float(c.Green)
                b = float(c.Blue)
                # Ensure it's distinctly blue
                if b > r * 1.2 and b > g * 1.2 and b > 0.3:
                    has_blue_style = True
                    break
            except Exception:
                continue

        # 3. Count walls assigned to "Audit_Blue"
        def is_audit_blue(m):
            if not m: return False
            if m.is_a("IfcMaterial") and m.Name == "Audit_Blue": return True
            if m.is_a("IfcMaterialLayerSetUsage"):
                return any(layer.Material and layer.Material.Name == "Audit_Blue" 
                           for layer in getattr(m.ForLayerSet, 'MaterialLayers', []))
            if m.is_a("IfcMaterialLayerSet"):
                return any(layer.Material and layer.Material.Name == "Audit_Blue" 
                           for layer in getattr(m, 'MaterialLayers', []))
            if m.is_a("IfcMaterialList"):
                return any(subm.Name == "Audit_Blue" for subm in getattr(m, 'Materials', []))
            return False

        assigned_walls = set()
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            if is_audit_blue(rel.RelatingMaterial):
                for obj in (rel.RelatedObjects or []):
                    if obj.is_a("IfcWall"):
                        assigned_walls.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "has_audit_blue": has_audit_blue,
            "has_blue_style": has_blue_style,
            "assigned_walls_count": len(assigned_walls),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "has_audit_blue": False,
            "has_blue_style": False,
            "assigned_walls_count": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_color_coding.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"has_audit_blue":false,"has_blue_style":false,"assigned_walls_count":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"