#!/bin/bash
echo "=== Exporting hvac_system_overlay result ==="

pkill -f librecad 2>/dev/null || true
sleep 3

DISPLAY=:1 import -window root /tmp/hvac_system_overlay_end.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, sys, re

OUTPUT_FILE = "/home/ga/Documents/LibreCAD/floorplan_hvac.dxf"
BASELINE_FILE = "/tmp/hvac_system_overlay_baseline.json"
TIMESTAMP_FILE = "/tmp/task_start_timestamp"

baseline = {"entity_count": 967, "layer_names": []}
if os.path.exists(BASELINE_FILE):
    try:
        with open(BASELINE_FILE) as f:
            baseline = json.load(f)
    except Exception:
        pass

task_start = 0
if os.path.exists(TIMESTAMP_FILE):
    try:
        task_start = int(open(TIMESTAMP_FILE).read().strip())
    except Exception:
        pass

result = {
    "output_exists": False,
    "file_modified_after_start": False,
    "file_size_bytes": 0,
    "layer_names": [],
    "total_entities": 0,
    "new_entity_count": 0,
    "entity_counts": {},
    "text_content": [],
    "new_layers_added": [],
    "hvac_supply_layer_present": False,
    "hvac_return_layer_present": False,
    "hvac_equip_or_notes_layer_present": False,
    "supply_line_count": 0,
    "return_line_count": 0,
    "circle_count_on_hvac_layers": 0,
    "total_circle_count": 0,
    "duct_sizing_text_count": 0,
    "equipment_label_present": False,
    "notes_text_present": False,
    "parse_error": None,
}

if not os.path.isfile(OUTPUT_FILE):
    with open("/tmp/hvac_system_overlay_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print("Output file not found.")
    sys.exit(0)

result["output_exists"] = True
result["file_size_bytes"] = os.path.getsize(OUTPUT_FILE)
mtime = os.path.getmtime(OUTPUT_FILE)
result["file_modified_after_start"] = int(mtime) > task_start

try:
    import ezdxf
    from collections import Counter

    doc = ezdxf.readfile(OUTPUT_FILE)
    msp = doc.modelspace()
    entities = list(msp)

    all_layers = [layer.dxf.name for layer in doc.layers]
    result["layer_names"] = all_layers
    original_upper = [l.upper() for l in baseline.get("layer_names", [])]
    new_layers = [l for l in all_layers if l.upper() not in original_upper]
    result["new_layers_added"] = new_layers
    new_upper = [l.upper() for l in new_layers]

    # HVAC layer detection - broad keyword matching for maximum flexibility
    supply_kw = ["SUPPLY", "SA", "M-SA", "HVAC-S", "HVAC_S", "AIR-SUPPLY", "DUCT-S",
                 "CONDITIONED", "SUPPLY-AIR", "SUPPLY-DUCT", "MECHANICAL-S", "M-SUPPLY"]
    return_kw = ["RETURN", "RA", "M-RA", "HVAC-R", "HVAC_R", "AIR-RETURN", "DUCT-R",
                 "RETURN-AIR", "RETURN-DUCT", "MECHANICAL-R", "M-RETURN"]
    equip_kw = ["EQUIP", "AHU", "UNIT", "HANDLER", "NOTES", "NOTE", "MECH", "HVAC",
                "MECHANICAL", "M-EQUIP", "M-NOTE", "M-ANNOT", "SCHEDULE"]

    result["hvac_supply_layer_present"] = any(any(kw in l for kw in supply_kw) for l in new_upper)
    result["hvac_return_layer_present"] = any(any(kw in l for kw in return_kw) for l in new_upper)
    result["hvac_equip_or_notes_layer_present"] = any(any(kw in l for kw in equip_kw) for l in new_upper)

    # If no explicit HVAC layers, check if there are any HVAC-themed new layers at all
    hvac_any_kw = supply_kw + return_kw + equip_kw + ["HVAC", "MECHANICAL", "DUCT", "M-"]
    hvac_new_layers = [l for l in new_upper if any(kw in l for kw in hvac_any_kw)]

    # Entity counts
    counts = Counter(e.dxftype() for e in entities)
    result["entity_counts"] = dict(counts)
    result["total_entities"] = len(entities)
    result["new_entity_count"] = max(0, len(entities) - baseline.get("entity_count", 967))

    # Count entities by type on new HVAC layers
    supply_layers_upper = [l for l in new_upper if any(kw in l for kw in supply_kw)]
    return_layers_upper = [l for l in new_upper if any(kw in l for kw in return_kw)]

    supply_lines = 0
    return_lines = 0
    circles_on_hvac = 0
    total_circles = 0
    text_list = []
    text_content = []

    for e in entities:
        try:
            layer = e.dxf.layer.upper()
            on_new = any(layer == nl.upper() for nl in new_layers)
            on_supply = any(layer == sl for sl in supply_layers_upper)
            on_return = any(layer == rl for rl in return_layers_upper)

            if e.dxftype() in ("LINE", "LWPOLYLINE", "POLYLINE"):
                if on_supply:
                    supply_lines += 1
                elif on_return:
                    return_lines += 1
            elif e.dxftype() in ("CIRCLE", "ARC"):
                total_circles += 1
                if on_new:
                    circles_on_hvac += 1

            if e.dxftype() == "TEXT":
                txt = e.dxf.text.strip().upper()
                if txt:
                    text_list.append(txt)
            elif e.dxftype() == "MTEXT":
                txt = e.text.strip().upper()
                if txt:
                    text_list.append(txt)
        except Exception:
            pass

    result["supply_line_count"] = supply_lines
    result["return_line_count"] = return_lines
    result["circle_count_on_hvac_layers"] = circles_on_hvac
    result["total_circle_count"] = total_circles
    result["text_content"] = text_list[:150]

    # Duct sizing text detection
    # Look for patterns like: 12x8, 10x6, 300 CFM, 200CFM, 8" duct, 12"x8"
    duct_sizing_pattern = re.compile(
        r'(\d+X\d+|\d+"?X\d+"?|\d+\s*CFM|\d+\s*FPM|\bSUPPLY\b|\bRETURN\b|\bDIFFUSER\b|\bGRILLE\b)',
        re.IGNORECASE
    )
    duct_sizing_count = sum(
        1 for txt in text_list
        if duct_sizing_pattern.search(txt)
    )
    result["duct_sizing_text_count"] = duct_sizing_count

    # Equipment label detection
    equip_text_kw = ["AHU", "AIR HANDLER", "UNIT", "CONDENSING", "FURNACE", "HEAT PUMP",
                     "AC", "A/C", "HVAC UNIT", "MECH UNIT", "EQUIPMENT"]
    result["equipment_label_present"] = any(
        any(kw in txt for kw in equip_text_kw) for txt in text_list
    )

    # Notes layer text
    notes_kw = ["NOTE", "CFM", "DUCT", "SIZING", "SCHEDULE", "SYSTEM", "RETURN", "SUPPLY"]
    result["notes_text_present"] = sum(
        1 for txt in text_list if any(kw in txt for kw in notes_kw)
    ) >= 2

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/hvac_system_overlay_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export complete. supply_layer={result['hvac_supply_layer_present']}, "
      f"return_layer={result['hvac_return_layer_present']}, "
      f"supply_lines={result['supply_line_count']}, "
      f"circles={result['total_circle_count']}, "
      f"duct_sizing_text={result['duct_sizing_text_count']}")
PYEOF

echo "=== Export Complete ==="
