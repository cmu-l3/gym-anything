#!/bin/bash
echo "=== Exporting ifc_uniclass_classification_commissioning result ==="

source /workspace/scripts/task_utils.sh || true

take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/uniclass_classification_result.json"

cat > /tmp/export_uniclass.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_classified.ifc"

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
        "n_walls": 0,
        "n_windows": 0,
        "n_doors": 0,
        "n_slabs": 0,
        "classification_systems": [],
        "walls_classified": 0,
        "windows_classified": 0,
        "doors_classified": 0,
        "slabs_classified": 0,
        "walls_code_correct": 0,
        "windows_code_correct": 0,
        "doors_code_correct": 0,
        "slabs_code_correct": 0
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Count elements
        walls = list(ifc.by_type("IfcWall")) + list(ifc.by_type("IfcWallStandardCase"))
        seen = set()
        unique_walls = []
        for w in walls:
            if w.id() not in seen:
                seen.add(w.id())
                unique_walls.append(w)
        walls = unique_walls

        windows = list(ifc.by_type("IfcWindow"))
        doors = list(ifc.by_type("IfcDoor"))
        slabs = list(ifc.by_type("IfcSlab"))

        # Collect all IfcClassification systems
        cls_systems = []
        for cls in ifc.by_type("IfcClassification"):
            cls_systems.append({
                "name": cls.Name or "",
                "source": getattr(cls, "Source", None) or "",
                "edition": getattr(cls, "Edition", None) or ""
            })

        WALL_CODE = "Ss_25_16_94"
        WINDOW_CODE = "Ss_25_96_57"
        DOOR_CODE = "Ss_25_32_33"
        SLAB_CODE = "Ss_25_56_95"

        def get_classification_refs(element):
            """Return list of (identification, name, system_name) for an element."""
            refs = []
            for inv in ifc.get_inverse(element):
                if inv.is_a("IfcRelAssociatesClassification"):
                    rc = inv.RelatingClassification
                    if rc and rc.is_a("IfcClassificationReference"):
                        ident = getattr(rc, "Identification", None) or getattr(rc, "ItemReference", None) or ""
                        ref_name = getattr(rc, "Name", None) or ""
                        sys_name = ""
                        rs = getattr(rc, "ReferencedSource", None)
                        if rs:
                            if rs.is_a("IfcClassification"):
                                sys_name = rs.Name or ""
                            elif rs.is_a("IfcClassificationReference"):
                                rs2 = getattr(rs, "ReferencedSource", None)
                                if rs2 and rs2.is_a("IfcClassification"):
                                    sys_name = rs2.Name or ""
                        refs.append((ident, ref_name, sys_name))
            return refs

        def count_classified_with_code(elements, expected_code):
            classified = 0
            code_correct = 0
            for el in elements:
                refs = get_classification_refs(el)
                if refs:
                    classified += 1
                    for ident, _, sys_name in refs:
                        if expected_code.lower() in ident.lower():
                            code_correct += 1
                            break
            return classified, code_correct

        walls_classified, walls_code_correct = count_classified_with_code(walls, WALL_CODE)
        windows_classified, windows_code_correct = count_classified_with_code(windows, WINDOW_CODE)
        doors_classified, doors_code_correct = count_classified_with_code(doors, DOOR_CODE)
        slabs_classified, slabs_code_correct = count_classified_with_code(slabs, SLAB_CODE)

        # Check for Uniclass 2015 system
        uniclass_system_found = any(
            "uniclass" in s["name"].lower() for s in cls_systems
        )

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_walls": len(walls),
            "n_windows": len(windows),
            "n_doors": len(doors),
            "n_slabs": len(slabs),
            "classification_systems": cls_systems,
            "uniclass_system_found": uniclass_system_found,
            "walls_classified": walls_classified,
            "windows_classified": windows_classified,
            "doors_classified": doors_classified,
            "slabs_classified": slabs_classified,
            "walls_code_correct": walls_code_correct,
            "windows_code_correct": windows_code_correct,
            "doors_code_correct": doors_code_correct,
            "slabs_code_correct": slabs_code_correct
        }

    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_walls": 0,
            "n_windows": 0,
            "n_doors": 0,
            "n_slabs": 0,
            "classification_systems": [],
            "uniclass_system_found": False,
            "walls_classified": 0,
            "windows_classified": 0,
            "doors_classified": 0,
            "slabs_classified": 0,
            "walls_code_correct": 0,
            "windows_code_correct": 0,
            "doors_code_correct": 0,
            "slabs_code_correct": 0,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result, default=str))
PYEOF

/opt/blender/blender --background --python /tmp/export_uniclass.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"task_start":0,"n_walls":0,"n_windows":0,"n_doors":0,"n_slabs":0,"classification_systems":[],"uniclass_system_found":false,"walls_classified":0,"windows_classified":0,"doors_classified":0,"slabs_classified":0,"walls_code_correct":0,"windows_code_correct":0,"doors_code_correct":0,"slabs_code_correct":0,"error":"Export produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
