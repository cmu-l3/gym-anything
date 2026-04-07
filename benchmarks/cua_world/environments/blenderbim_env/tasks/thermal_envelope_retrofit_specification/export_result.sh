#!/bin/bash
echo "=== Exporting thermal_envelope_retrofit_specification result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/thermal_envelope_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_thermal_envelope.py << 'PYEOF'
import sys
import json
import os

# Ensure ifcopenshell from Bonsai is in path
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_thermal_envelope.ifc"

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
        "task_start": task_start,
        "n_walls": 0,
        "n_windows": 0,
        "layer_sets": [],
        "walls_with_layerset": 0,
        "window_types": [],
        "windows_with_type": 0,
        "zones": []
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # ── Anti-gaming: count original model elements ────────────────
        walls = list(ifc.by_type("IfcWall")) + list(ifc.by_type("IfcWallStandardCase"))
        # Deduplicate (IfcWallStandardCase is a subtype of IfcWall)
        wall_ids = set()
        unique_walls = []
        for w in walls:
            if w.id() not in wall_ids:
                wall_ids.add(w.id())
                unique_walls.append(w)
        walls = unique_walls
        n_walls = len(walls)

        windows = list(ifc.by_type("IfcWindow"))
        n_windows = len(windows)

        # ── Section A: Material Layer Sets ────────────────────────────
        layer_sets_data = []
        for ls in ifc.by_type("IfcMaterialLayerSet"):
            layers = []
            for layer in (ls.MaterialLayers or []):
                mat_name = None
                if layer.Material:
                    mat_name = layer.Material.Name
                layers.append({
                    "material": mat_name,
                    "thickness": layer.LayerThickness
                })
            ls_name = getattr(ls, "LayerSetName", None) or getattr(ls, "MaterialSetName", None) or ""
            layer_sets_data.append({
                "name": ls_name,
                "layer_count": len(layers),
                "layers": layers
            })

        # Count walls assigned to a MULTI-LAYER set (>= 3 layers).
        # The original model has only 1-layer sets, so this only counts
        # walls that the agent reassigned to a new composite layer set.
        walls_with_layerset = 0
        for w in walls:
            for inv in ifc.get_inverse(w):
                if inv.is_a("IfcRelAssociatesMaterial"):
                    mat = inv.RelatingMaterial
                    actual_ls = None
                    if mat and mat.is_a("IfcMaterialLayerSetUsage"):
                        actual_ls = mat.ForLayerSet
                    elif mat and mat.is_a("IfcMaterialLayerSet"):
                        actual_ls = mat
                    if actual_ls and len(actual_ls.MaterialLayers or []) >= 3:
                        walls_with_layerset += 1
                    break

        # ── Section B: Window Types ───────────────────────────────────
        window_types_data = []
        for wt in ifc.by_type("IfcWindowType"):
            props = {}
            # Check HasPropertySets on the type directly
            if hasattr(wt, "HasPropertySets") and wt.HasPropertySets:
                for pset in wt.HasPropertySets:
                    if pset.is_a("IfcPropertySet"):
                        for p in (pset.HasProperties or []):
                            if hasattr(p, "NominalValue") and p.NominalValue:
                                try:
                                    props[p.Name] = float(p.NominalValue.wrappedValue)
                                except (ValueError, TypeError, AttributeError):
                                    props[p.Name] = str(p.NominalValue.wrappedValue)

            # Also check via IfcRelDefinesByProperties
            for inv in ifc.get_inverse(wt):
                if inv.is_a("IfcRelDefinesByProperties"):
                    pdef = inv.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet"):
                        for p in (pdef.HasProperties or []):
                            if hasattr(p, "NominalValue") and p.NominalValue:
                                try:
                                    props[p.Name] = float(p.NominalValue.wrappedValue)
                                except (ValueError, TypeError, AttributeError):
                                    props[p.Name] = str(p.NominalValue.wrappedValue)

            window_types_data.append({
                "name": wt.Name or "",
                "properties": props
            })

        # Count windows assigned to any IfcWindowType
        windows_with_type = 0
        for rel in ifc.by_type("IfcRelDefinesByType"):
            rt = rel.RelatingType
            if rt and rt.is_a("IfcWindowType"):
                for obj in (rel.RelatedObjects or []):
                    if obj.is_a("IfcWindow"):
                        windows_with_type += 1

        # ── Section C: Zones ──────────────────────────────────────────
        zones_data = []
        for z in ifc.by_type("IfcZone"):
            members = []
            for inv in ifc.get_inverse(z):
                if inv.is_a("IfcRelAssignsToGroup") and inv.RelatingGroup == z:
                    for obj in (inv.RelatedObjects or []):
                        members.append({
                            "name": obj.Name or obj.LongName or "",
                            "class": obj.is_a()
                        })
            zones_data.append({
                "name": z.Name or "",
                "member_count": len(members),
                "members": members
            })

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_walls": n_walls,
            "n_windows": n_windows,
            "layer_sets": layer_sets_data,
            "walls_with_layerset": walls_with_layerset,
            "window_types": window_types_data,
            "windows_with_type": windows_with_type,
            "zones": zones_data
        }

    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_walls": 0,
            "n_windows": 0,
            "layer_sets": [],
            "walls_with_layerset": 0,
            "window_types": [],
            "windows_with_type": 0,
            "zones": [],
            "error": str(e)
        }

print("RESULT:" + json.dumps(result, default=str))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_thermal_envelope.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"task_start":0,"n_walls":0,"n_windows":0,"layer_sets":[],"walls_with_layerset":0,"window_types":[],"windows_with_type":0,"zones":[],"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"


<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
