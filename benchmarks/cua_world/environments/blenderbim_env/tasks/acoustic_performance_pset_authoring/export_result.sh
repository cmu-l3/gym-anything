#!/bin/bash
echo "=== Exporting acoustic_performance_pset_authoring result ==="

source /workspace/scripts/task_utils.sh || true

take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/acoustic_pset_result.json"

cat > /tmp/export_acoustic_pset.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_acoustic.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

EMPTY = {
    "file_exists": False, "file_mtime": 0.0, "task_start": task_start,
    "n_ew_walls": 0, "n_iw_walls": 0,
    "ew_walls_with_acoustic_rating": 0, "ew_acoustic_rating_correct": 0,
    "iw_walls_with_custom_pset": 0,
    "iw_stc_correct": 0, "iw_iic_correct": 0, "iw_flanking_correct": 0,
    "zones": []
}

if not os.path.exists(ifc_path):
    result = EMPTY
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        walls = list(ifc.by_type("IfcWall")) + list(ifc.by_type("IfcWallStandardCase"))
        seen = set()
        unique_walls = []
        for w in walls:
            if w.id() not in seen:
                seen.add(w.id())
                unique_walls.append(w)

        ew_walls = [w for w in unique_walls if (w.Name or "").upper().startswith("EW")]
        iw_walls = [w for w in unique_walls if (w.Name or "").upper().startswith("IW")]

        def get_pset_props(element, pset_name):
            """Return dict of property name→value for a given pset on an element."""
            props = {}
            for inv in ifc.get_inverse(element):
                if inv.is_a("IfcRelDefinesByProperties"):
                    pdef = inv.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet"):
                        if pset_name.lower() in pdef.Name.lower():
                            for p in (pdef.HasProperties or []):
                                if hasattr(p, "NominalValue") and p.NominalValue:
                                    try:
                                        props[p.Name] = p.NominalValue.wrappedValue
                                    except Exception:
                                        props[p.Name] = str(p.NominalValue)
            return props

        # Section 1: External walls - AcousticRating in Pset_WallCommon
        ew_with_rating = 0
        ew_rating_correct = 0
        for w in ew_walls:
            props = get_pset_props(w, "Pset_WallCommon")
            if "AcousticRating" in props:
                ew_with_rating += 1
                val = str(props["AcousticRating"])
                if "52" in val and "dB" in val.upper():
                    ew_rating_correct += 1

        # Section 2: Internal walls - Pset_AcousticPerformance
        iw_with_custom_pset = 0
        iw_stc_correct = 0
        iw_iic_correct = 0
        iw_flanking_correct = 0
        for w in iw_walls:
            props = get_pset_props(w, "Pset_AcousticPerformance")
            if props:
                iw_with_custom_pset += 1
                # SoundTransmissionClass == 45
                stc = props.get("SoundTransmissionClass")
                try:
                    if int(stc) == 45:
                        iw_stc_correct += 1
                except Exception:
                    pass
                # ImpactInsulationClass == 50
                iic = props.get("ImpactInsulationClass")
                try:
                    if int(iic) == 50:
                        iw_iic_correct += 1
                except Exception:
                    pass
                # FlankingTransmission == "Controlled"
                flank = props.get("FlankingTransmission")
                if flank and "controlled" in str(flank).lower():
                    iw_flanking_correct += 1

        # Section 3: Zones
        zones_data = []
        for z in ifc.by_type("IfcZone"):
            members = []
            for inv in ifc.get_inverse(z):
                if inv.is_a("IfcRelAssignsToGroup") and inv.RelatingGroup == z:
                    for obj in (inv.RelatedObjects or []):
                        members.append({"name": obj.Name or obj.LongName or "", "class": obj.is_a()})
            zones_data.append({
                "name": z.Name or "",
                "member_count": len(members),
                "members": members
            })

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_ew_walls": len(ew_walls),
            "n_iw_walls": len(iw_walls),
            "ew_walls_with_acoustic_rating": ew_with_rating,
            "ew_acoustic_rating_correct": ew_rating_correct,
            "iw_walls_with_custom_pset": iw_with_custom_pset,
            "iw_stc_correct": iw_stc_correct,
            "iw_iic_correct": iw_iic_correct,
            "iw_flanking_correct": iw_flanking_correct,
            "zones": zones_data
        }

    except Exception as e:
        result = dict(EMPTY)
        result.update({"file_exists": True, "file_mtime": os.path.getmtime(ifc_path), "error": str(e)})

print("RESULT:" + json.dumps(result, default=str))
PYEOF

/opt/blender/blender --background --python /tmp/export_acoustic_pset.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"error":"Export produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
