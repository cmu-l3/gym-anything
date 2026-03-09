#!/bin/bash
echo "=== Exporting electrical_panel_schedule result ==="

pkill -f librecad 2>/dev/null || true
sleep 3

DISPLAY=:1 import -window root /tmp/electrical_panel_schedule_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, sys, re

output_file = "/home/ga/Documents/LibreCAD/floorplan_electrical.dxf"
result_file = "/tmp/electrical_panel_schedule_result.json"
baseline_file = "/tmp/electrical_panel_schedule_baseline.json"
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
    "panel_layer_found": False,
    "panel_layer_names": [],
    "circuit_layer_found": False,
    "circuit_layer_names": [],
    "notes_layer_found": False,
    "notes_layer_names": [],
    "panel_table_lines": 0,
    "circuit_description_count": 0,
    "circuit_descriptions": [],
    "load_text_count": 0,
    "load_texts": [],
    "main_breaker_found": False,
    "main_breaker_texts": [],
    "electrical_note_count": 0,
    "circuit_number_count": 0,
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
    PANEL_KW = ["E-PANEL", "PANEL", "SCHEDULE", "ELEC-PANEL", "E_PANEL",
                "ELECTRICAL-PANEL", "PANELBOARD", "LOADCENTER"]
    CIRCUIT_KW = ["E-CIRCUIT", "CIRCUIT", "BRANCH", "E-BRANCH", "ELEC-CKT",
                  "CKT", "WIRING", "E-WIRE", "ELEC"]
    NOTES_KW = ["E-NOTE", "ELEC-NOTE", "ELECTRICAL-NOTE", "E-SPEC",
                "NOTE", "SPECIFICATION", "ELECTRICAL-SPEC", "E-ANNO"]

    panel_layers = set()
    circuit_layers = set()
    notes_layers = set()

    for ln in new_layers:
        ln_up = ln.upper()
        if any(kw in ln_up for kw in PANEL_KW):
            panel_layers.add(ln)
        if any(kw in ln_up for kw in CIRCUIT_KW):
            circuit_layers.add(ln)
        if any(kw in ln_up for kw in NOTES_KW):
            notes_layers.add(ln)

    result["panel_layer_found"] = len(panel_layers) > 0
    result["panel_layer_names"] = list(panel_layers)
    result["circuit_layer_found"] = len(circuit_layers) > 0
    result["circuit_layer_names"] = list(circuit_layers)
    result["notes_layer_found"] = len(notes_layers) > 0
    result["notes_layer_names"] = list(notes_layers)

    # All electrical-related layers
    elec_layers = panel_layers | circuit_layers | notes_layers
    for ln in new_layers:
        if any(kw in ln.upper() for kw in ["ELEC", "E-", "PANEL", "CIRCUIT", "POWER"]):
            elec_layers.add(ln)

    # Patterns for electrical content
    # Load pattern: number followed by W, VA, kW, A, AMP
    load_pattern = re.compile(
        r'\b\d+\.?\d*\s*(?:W\b|VA\b|KW\b|kW\b|KVA\b|kVA\b|A\b|AMP\b|AMPS\b|WATTS\b)',
        re.IGNORECASE
    )
    # Main breaker pattern: "200A", "100 AMP", "200 MAIN", "MAIN 200A"
    main_breaker_pattern = re.compile(
        r'\b(?:MAIN|MSB|MDP|PANEL\s*RATING|(?:\d+\s*A(?:MP)?S?\s*MAIN)|\d+\s*A(?:MP)?S?\b)',
        re.IGNORECASE
    )
    main_breaker_specific = re.compile(
        r'\b(?:200|150|100|60)\s*(?:A\b|AMP\b|AMPS\b)',
        re.IGNORECASE
    )
    # Circuit number pattern: "CKT 1", "#1", "CIRCUIT 1", "BR-1"
    circuit_num_pattern = re.compile(
        r'\b(?:CKT|BR|CIRCUIT|C)\s*[-#]?\s*\d+\b',
        re.IGNORECASE
    )
    # Circuit description keywords (typical branch circuits)
    CIRCUIT_DESC_KW = [
        "LIGHTING", "RECEPTACLE", "OUTLET", "HVAC", "A/C", "DRYER",
        "WASHER", "RANGE", "OVEN", "DISHWASHER", "MICROWAVE", "REFRIGERATOR",
        "GARAGE", "EXTERIOR", "KITCHEN", "BATH", "BEDROOM", "GENERAL",
        "SPARE", "SPACE", "RESERVED", "SMOKE", "GFI", "GFCI"
    ]

    panel_table_lines = 0
    circuit_descriptions = []
    load_texts = []
    main_breaker_texts = []
    all_text_content = []
    circuit_numbers = set()
    electrical_notes = 0

    for entity in all_entities:
        layer = entity.dxf.layer if hasattr(entity.dxf, 'layer') else "0"
        layer_up = layer.upper()

        # Count lines that form panel table (lines on panel or any new elec layer)
        if entity.dxftype() in ('LINE', 'LWPOLYLINE'):
            if layer in panel_layers or any(kw in layer_up for kw in PANEL_KW):
                panel_table_lines += 1

        # Collect text
        text_val = None
        if entity.dxftype() == 'TEXT':
            text_val = entity.dxf.text if hasattr(entity.dxf, 'text') else ''
        elif entity.dxftype() == 'MTEXT':
            text_val = entity.plain_mtext() if hasattr(entity, 'plain_mtext') else (
                entity.dxf.text if hasattr(entity.dxf, 'text') else '')

        if text_val and text_val.strip():
            all_text_content.append(text_val.strip())
            t_up = text_val.upper()

            # Circuit descriptions
            for kw in CIRCUIT_DESC_KW:
                if kw in t_up and text_val.strip() not in circuit_descriptions:
                    circuit_descriptions.append(text_val.strip())
                    break

            # Load calculations
            if load_pattern.search(text_val):
                load_texts.append(text_val.strip())

            # Main breaker
            if main_breaker_specific.search(text_val) or ("MAIN" in t_up and re.search(r'\d+', t_up)):
                main_breaker_texts.append(text_val.strip())
                result["main_breaker_found"] = True

            # Circuit numbers
            m = circuit_num_pattern.search(text_val)
            if m:
                circuit_numbers.add(m.group(0).strip())

            # Electrical notes
            if any(kw in t_up for kw in ["NOTE", "SPEC", "REQUIRE", "INSTALL", "GENERAL"]):
                electrical_notes += 1

    result["panel_table_lines"] = panel_table_lines
    result["circuit_description_count"] = len(circuit_descriptions)
    result["circuit_descriptions"] = circuit_descriptions[:20]
    result["load_text_count"] = len(load_texts)
    result["load_texts"] = load_texts[:20]
    result["main_breaker_texts"] = main_breaker_texts[:10]
    result["circuit_number_count"] = len(circuit_numbers)
    result["electrical_note_count"] = electrical_notes
    result["all_text_content"] = all_text_content[:100]

    print(f"Analysis complete:")
    print(f"  New layers: {result['new_layer_count']} ({result['new_layer_names']})")
    print(f"  Panel layers: {result['panel_layer_names']}")
    print(f"  Circuit layers: {result['circuit_layer_names']}")
    print(f"  Panel table lines: {panel_table_lines}")
    print(f"  Circuit descriptions: {len(circuit_descriptions)} ({circuit_descriptions[:3]})")
    print(f"  Load texts: {len(load_texts)} ({load_texts[:2]})")
    print(f"  Main breaker: {result['main_breaker_found']} ({main_breaker_texts[:2]})")
    print(f"  Circuit numbers: {len(circuit_numbers)}")

except Exception as e:
    result["error"] = str(e)
    print(f"ERROR during DXF analysis: {e}")
    import traceback
    traceback.print_exc()

with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_file}")
PYEOF

echo "=== electrical_panel_schedule export complete ==="
