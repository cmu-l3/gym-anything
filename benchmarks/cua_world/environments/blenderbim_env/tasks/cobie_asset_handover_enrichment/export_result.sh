#!/bin/bash
echo "=== Exporting cobie_asset_handover_enrichment result ==="

source /workspace/scripts/task_utils.sh || true

take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/cobie_handover_result.json"

cat > /tmp/export_cobie_handover.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_cobie.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

EMPTY = {
    "file_exists": False, "file_mtime": 0.0, "task_start": task_start,
    "n_windows": 0, "n_doors": 0,
    "windows_with_mfr_pset": 0, "window_mfr_name_correct": 0,
    "window_model_correct": 0, "window_gtin_correct": 0,
    "doors_with_mfr_pset": 0, "door_mfr_name_correct": 0,
    "door_model_correct": 0, "door_gtin_correct": 0,
    "windows_with_window_common": 0,
    "window_thermal_correct": 0, "window_glazing_correct": 0, "window_external_correct": 0,
    "glazing_group_found": False, "glazing_group_window_count": 0
}

if not os.path.exists(ifc_path):
    result = EMPTY
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        windows = list(ifc.by_type("IfcWindow"))
        doors = list(ifc.by_type("IfcDoor"))

        def get_pset_props(element, pset_name_fragment):
            props = {}
            for inv in ifc.get_inverse(element):
                if inv.is_a("IfcRelDefinesByProperties"):
                    pdef = inv.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet"):
                        if pset_name_fragment.lower() in pdef.Name.lower():
                            for p in (pdef.HasProperties or []):
                                if hasattr(p, "NominalValue") and p.NominalValue:
                                    try:
                                        props[p.Name] = p.NominalValue.wrappedValue
                                    except Exception:
                                        props[p.Name] = str(p.NominalValue)
            return props

        # Section 1: Window manufacturer data
        windows_with_mfr = 0
        window_mfr_correct = 0
        window_model_correct = 0
        window_gtin_correct = 0
        for w in windows:
            props = get_pset_props(w, "ManufacturerTypeInformation")
            if props:
                windows_with_mfr += 1
                mfr = str(props.get("Manufacturer", ""))
                if "schuco" in mfr.lower() or "schüco" in mfr.lower():
                    window_mfr_correct += 1
                model = str(props.get("ModelLabel", ""))
                if "fw" in model.lower() and "60" in model:
                    window_model_correct += 1
                gtin = str(props.get("GlobalTradeItemNumber", ""))
                if "4012236013245" in gtin:
                    window_gtin_correct += 1

        # Section 2: Door manufacturer data
        doors_with_mfr = 0
        door_mfr_correct = 0
        door_model_correct = 0
        door_gtin_correct = 0
        for d in doors:
            props = get_pset_props(d, "ManufacturerTypeInformation")
            if props:
                doors_with_mfr += 1
                mfr = str(props.get("Manufacturer", ""))
                if "hormann" in mfr.lower() or "hörmann" in mfr.lower():
                    door_mfr_correct += 1
                model = str(props.get("ModelLabel", ""))
                if "thp" in model.lower() and "universal" in model.lower():
                    door_model_correct += 1
                gtin = str(props.get("GlobalTradeItemNumber", ""))
                if "4034598167823" in gtin:
                    door_gtin_correct += 1

        # Section 3: Window common properties
        windows_with_common = 0
        thermal_correct = 0
        glazing_correct = 0
        external_correct = 0
        for w in windows:
            props = get_pset_props(w, "WindowCommon")
            if props:
                windows_with_common += 1
                # ThermalTransmittance ≈ 1.1
                tt = props.get("ThermalTransmittance")
                try:
                    if abs(float(tt) - 1.1) < 0.05:
                        thermal_correct += 1
                except Exception:
                    pass
                # GlazingAreaFraction ≈ 0.7
                gaf = props.get("GlazingAreaFraction")
                try:
                    if abs(float(gaf) - 0.7) < 0.05:
                        glazing_correct += 1
                except Exception:
                    pass
                # IsExternal == True
                ie = props.get("IsExternal")
                if ie is True or str(ie).upper() in ("TRUE", "1", "YES"):
                    external_correct += 1

        # Section 4: Glazing Package group
        glazing_group_found = False
        glazing_window_count = 0
        for grp in ifc.by_type("IfcGroup"):
            if "glazing" in (grp.Name or "").lower():
                glazing_group_found = True
                for inv in ifc.get_inverse(grp):
                    if inv.is_a("IfcRelAssignsToGroup") and inv.RelatingGroup == grp:
                        glazing_window_count = sum(
                            1 for obj in (inv.RelatedObjects or []) if obj.is_a("IfcWindow")
                        )
                break

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "n_windows": len(windows),
            "n_doors": len(doors),
            "windows_with_mfr_pset": windows_with_mfr,
            "window_mfr_name_correct": window_mfr_correct,
            "window_model_correct": window_model_correct,
            "window_gtin_correct": window_gtin_correct,
            "doors_with_mfr_pset": doors_with_mfr,
            "door_mfr_name_correct": door_mfr_correct,
            "door_model_correct": door_model_correct,
            "door_gtin_correct": door_gtin_correct,
            "windows_with_window_common": windows_with_common,
            "window_thermal_correct": thermal_correct,
            "window_glazing_correct": glazing_correct,
            "window_external_correct": external_correct,
            "glazing_group_found": glazing_group_found,
            "glazing_group_window_count": glazing_window_count
        }

    except Exception as e:
        result = dict(EMPTY)
        result.update({"file_exists": True, "file_mtime": os.path.getmtime(ifc_path), "error": str(e)})

print("RESULT:" + json.dumps(result, default=str))
PYEOF

/opt/blender/blender --background --python /tmp/export_cobie_handover.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"error":"Export produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
