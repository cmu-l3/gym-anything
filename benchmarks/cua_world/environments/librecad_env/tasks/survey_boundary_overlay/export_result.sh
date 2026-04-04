#!/bin/bash
echo "=== Exporting survey_boundary_overlay result ==="

pkill -f librecad 2>/dev/null || true
sleep 3

DISPLAY=:1 import -window root /tmp/survey_boundary_overlay_final.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/LibreCAD/floorplan_survey.dxf"

python3 << 'PYEOF'
import json, os, sys, re

output_file = "/home/ga/Documents/LibreCAD/floorplan_survey.dxf"
result_file = "/tmp/survey_boundary_overlay_result.json"
baseline_file = "/tmp/survey_boundary_overlay_baseline.json"
timestamp_file = "/tmp/task_start_timestamp"

result = {
    "output_file_exists": False,
    "output_file_mtime": 0,
    "task_start_timestamp": 0,
    "file_size_bytes": 0,
    "total_entity_count": 0,
    "baseline_entity_count": 967,
    "new_entity_count": 0,
    "baseline_layer_count": 0,
    "total_layer_count": 0,
    "new_layer_count": 0,
    "layer_names": [],
    "new_layer_names": [],
    "boundary_layer_found": False,
    "boundary_layer_names": [],
    "setback_layer_found": False,
    "setback_layer_names": [],
    "easement_layer_found": False,
    "easement_layer_names": [],
    "survey_text_layer_found": False,
    "north_arrow_layer_found": False,
    "boundary_line_count": 0,
    "bearing_text_count": 0,
    "bearing_texts": [],
    "distance_text_count": 0,
    "easement_entity_count": 0,
    "legend_text_found": False,
    "north_arrow_found": False,
    "all_text_content": [],
    "error": None
}

# Load baseline
try:
    with open(baseline_file, 'r') as f:
        baseline = json.load(f)
    result["baseline_entity_count"] = baseline.get("entity_count", 967)
    baseline_layers = set(baseline.get("layer_names", []))
    result["baseline_layer_count"] = len(baseline_layers)
except Exception as e:
    baseline_layers = set()

# Load task start timestamp
try:
    with open(timestamp_file, 'r') as f:
        result["task_start_timestamp"] = int(f.read().strip())
except Exception:
    pass

# Check output file
if not os.path.exists(output_file):
    result["output_file_exists"] = False
    result["error"] = "Output file not found"
    with open(result_file, 'w') as f:
        json.dump(result, f, indent=2)
    print("ERROR: Output file not found")
    sys.exit(0)

result["output_file_exists"] = True
stat = os.stat(output_file)
result["output_file_mtime"] = int(stat.st_mtime)
result["file_size_bytes"] = stat.st_size

try:
    import ezdxf

    doc = ezdxf.readfile(output_file)
    msp = doc.modelspace()

    all_entities = list(msp)
    result["total_entity_count"] = len(all_entities)
    result["new_entity_count"] = len(all_entities) - result["baseline_entity_count"]

    all_layers = [l.dxf.name for l in doc.layers]
    result["layer_names"] = all_layers
    result["total_layer_count"] = len(all_layers)
    new_layers = [l for l in all_layers if l not in baseline_layers]
    result["new_layer_names"] = new_layers
    result["new_layer_count"] = len(new_layers)

    # Layer classification keywords
    BOUNDARY_KW = ["PROPERTY", "BOUNDARY", "LOT", "PARCEL", "SURVEY", "C-PROP",
                   "PROP-LINE", "PROPLINE", "LEGAL", "PLAT", "CADASTRAL"]
    SETBACK_KW = ["SETBACK", "BUILDING LINE", "BLDG-LINE", "ZONING", "ZONE",
                  "SET-BACK", "REQUIRED", "FRONT", "REAR", "SIDE"]
    EASEMENT_KW = ["EASEMENT", "ESMT", "UTILITY", "ACCESS", "RIGHT-OF-WAY",
                   "ROW", "DRAINAGE", "INGRESS", "EGRESS"]
    SURVEY_TEXT_KW = ["BEARING", "DIMENSION", "ANNO", "TEXT", "SURVEY-ANNO",
                      "SURVEY-TEXT", "LABEL", "NOTES", "NOTE"]
    NORTH_KW = ["NORTH", "ARROW", "COMPASS", "ORIENT", "DIRECTION"]

    boundary_layers = set()
    setback_layers = set()
    easement_layers = set()
    survey_text_layers = set()
    north_arrow_layers = set()

    for ln in new_layers:
        ln_up = ln.upper()
        if any(kw in ln_up for kw in BOUNDARY_KW):
            boundary_layers.add(ln)
        if any(kw in ln_up for kw in SETBACK_KW):
            setback_layers.add(ln)
        if any(kw in ln_up for kw in EASEMENT_KW):
            easement_layers.add(ln)
        if any(kw in ln_up for kw in SURVEY_TEXT_KW):
            survey_text_layers.add(ln)
        if any(kw in ln_up for kw in NORTH_KW):
            north_arrow_layers.add(ln)

    result["boundary_layer_found"] = len(boundary_layers) > 0
    result["boundary_layer_names"] = list(boundary_layers)
    result["setback_layer_found"] = len(setback_layers) > 0
    result["setback_layer_names"] = list(setback_layers)
    result["easement_layer_found"] = len(easement_layers) > 0
    result["easement_layer_names"] = list(easement_layers)
    result["survey_text_layer_found"] = len(survey_text_layers) > 0
    result["north_arrow_layer_found"] = len(north_arrow_layers) > 0

    # All new layers (for partial scoring when layer names don't match keywords)
    # Count line entities on boundary, setback, easement layers
    relevant_layers = boundary_layers | setback_layers | easement_layers
    # Also check any layer with SURVEY in name
    for ln in new_layers:
        if "SURVEY" in ln.upper() or "BOUND" in ln.upper() or "PROP" in ln.upper():
            relevant_layers.add(ln)

    boundary_lines = 0
    easement_entities = 0
    all_text_content = []
    bearing_texts = []
    distance_texts = []

    # Bearing pattern: N/S, digits, degrees symbol or d, minutes, E/W
    # e.g. "N45°30'E", "S12d15'30\"W", "N 45-30 E", "N45.5E"
    bearing_pattern = re.compile(
        r'\b[NSns]\s*\d+[\d°d\.\-\s]*[\'\"m]?\s*[EWew]\b',
        re.IGNORECASE
    )
    # Distance pattern: number followed by unit
    # e.g. "125.00'", "48.5 FT", "15.25 M", "200.00"
    distance_pattern = re.compile(
        r'\b\d+\.?\d*\s*(?:\'|FT|FEET|M|METERS|LF)?\b',
        re.IGNORECASE
    )

    for entity in all_entities:
        layer = entity.dxf.layer if hasattr(entity.dxf, 'layer') else "0"
        layer_up = layer.upper()

        # Count lines on boundary/property layers
        if entity.dxftype() in ('LINE', 'LWPOLYLINE', 'POLYLINE', 'SPLINE'):
            if layer in relevant_layers or any(kw in layer_up for kw in BOUNDARY_KW):
                boundary_lines += 1
            if layer in easement_layers or any(kw in layer_up for kw in EASEMENT_KW):
                easement_entities += 1

        # Collect text
        text_val = None
        if entity.dxftype() == 'TEXT':
            text_val = entity.dxf.text if hasattr(entity.dxf, 'text') else ''
        elif entity.dxftype() == 'MTEXT':
            text_val = entity.plain_mtext() if hasattr(entity, 'plain_mtext') else (
                entity.dxf.text if hasattr(entity.dxf, 'text') else '')

        if text_val and text_val.strip():
            all_text_content.append(text_val.strip())

            # Check for bearing notation
            if bearing_pattern.search(text_val):
                bearing_texts.append(text_val.strip())

            # Check for distance with feet/meters
            dist_match = re.search(r"\d+\.?\d*\s*(?:'|FT|FEET|M\b|LF)", text_val, re.IGNORECASE)
            if dist_match:
                distance_texts.append(text_val.strip())

    result["boundary_line_count"] = boundary_lines
    result["easement_entity_count"] = easement_entities
    result["bearing_text_count"] = len(bearing_texts)
    result["bearing_texts"] = bearing_texts[:20]
    result["distance_text_count"] = len(distance_texts)
    result["all_text_content"] = all_text_content[:100]

    # Check for legend/notes text
    LEGEND_KW = ["LEGEND", "NOTES", "NOTE:", "GENERAL NOTE", "SURVEY NOTE",
                 "ABBREVIATION", "SYMBOL", "BOUNDARY LEGEND", "SURVEYOR"]
    NORTH_TEXT_KW = ["NORTH", "N", "TRUE NORTH", "MAGNETIC NORTH"]

    for t in all_text_content:
        t_up = t.upper()
        if any(kw in t_up for kw in LEGEND_KW):
            result["legend_text_found"] = True
        if any(kw in t_up for kw in NORTH_TEXT_KW) and len(t) <= 20:
            result["north_arrow_found"] = True

    # North arrow might also be a circle or block with NORTH in name
    if result["north_arrow_layer_found"]:
        result["north_arrow_found"] = True

    print(f"Analysis complete:")
    print(f"  New layers: {result['new_layer_count']} ({result['new_layer_names']})")
    print(f"  Boundary layers: {result['boundary_layer_names']}")
    print(f"  Setback layers: {result['setback_layer_names']}")
    print(f"  Easement layers: {result['easement_layer_names']}")
    print(f"  Boundary lines: {boundary_lines}")
    print(f"  Bearing texts: {len(bearing_texts)} ({bearing_texts[:3]})")
    print(f"  Legend found: {result['legend_text_found']}")
    print(f"  North arrow found: {result['north_arrow_found']}")

except Exception as e:
    result["error"] = str(e)
    print(f"ERROR during DXF analysis: {e}")
    import traceback
    traceback.print_exc()

with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_file}")
PYEOF

echo "=== survey_boundary_overlay export complete ==="
