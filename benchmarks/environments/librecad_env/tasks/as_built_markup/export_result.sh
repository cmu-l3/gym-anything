#!/bin/bash
echo "=== Exporting as_built_markup result ==="

# Kill LibreCAD to ensure the DXF is fully flushed to disk
pkill -f librecad 2>/dev/null || true
sleep 3

# Take final screenshot
DISPLAY=:1 import -window root /tmp/as_built_markup_end.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/LibreCAD/floorplan_asbuilt.dxf"

python3 << 'PYEOF'
import json, os, sys

OUTPUT_FILE = "/home/ga/Documents/LibreCAD/floorplan_asbuilt.dxf"
BASELINE_FILE = "/tmp/as_built_markup_baseline.json"
TIMESTAMP_FILE = "/tmp/task_start_timestamp"

# Load baseline
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
    "text_layers": [],
    "asbuilt_layer_present": False,
    "change_or_note_layer_present": False,
    "asbuilt_stamp_text_present": False,
    "field_change_text_count": 0,
    "new_layers_added": [],
    "parse_error": None,
}

if not os.path.isfile(OUTPUT_FILE):
    with open("/tmp/as_built_markup_result.json", "w") as f:
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

    # Layer analysis
    all_layers = [layer.dxf.name for layer in doc.layers]
    result["layer_names"] = all_layers
    original_layer_names_upper = [l.upper() for l in baseline.get("layer_names", [])]
    new_layers = [l for l in all_layers if l.upper() not in original_layer_names_upper]
    result["new_layers_added"] = new_layers
    new_layers_upper = [l.upper() for l in new_layers]

    # Check for as-built themed layer
    asbuilt_kw = ["AS-BUILT", "ASBUILT", "AS_BUILT", "RECORD", "A-ABLT", "ABLT", "FIELD-VERIFIED"]
    result["asbuilt_layer_present"] = any(
        any(kw in l for kw in asbuilt_kw) for l in new_layers_upper
    )

    # Check for change/notes/markup layer
    change_kw = ["CHANGE", "FIELD", "MARKUP", "REVISION", "REV", "NOTES", "NOTE", "DELTA", "MARK", "ANNOT"]
    result["change_or_note_layer_present"] = any(
        any(kw in l for kw in change_kw) for l in new_layers_upper
    )

    # Entity counts
    counts = Counter(e.dxftype() for e in entities)
    result["entity_counts"] = dict(counts)
    result["total_entities"] = len(entities)
    result["new_entity_count"] = max(0, len(entities) - baseline.get("entity_count", 967))

    # Text analysis
    text_list = []
    text_layers = []
    for e in entities:
        try:
            if e.dxftype() == "TEXT":
                txt = e.dxf.text.strip().upper()
                layer = e.dxf.layer.upper()
                if txt:
                    text_list.append(txt)
                    text_layers.append(layer)
            elif e.dxftype() == "MTEXT":
                txt = e.text.strip().upper()
                layer = e.dxf.layer.upper()
                if txt:
                    text_list.append(txt)
                    text_layers.append(layer)
        except Exception:
            pass

    result["text_content"] = text_list[:150]
    result["text_layers"] = text_layers[:150]

    # As-built stamp text check
    stamp_kw = ["AS-BUILT", "AS BUILT", "ASBUILT", "RECORD DRAWING", "FOR RECORD", "ISSUED FOR RECORD",
                "AS CONSTRUCTED", "AS CONSTRUCTED", "FIELD VERIFIED", "RECORD OF CONSTRUCTION"]
    result["asbuilt_stamp_text_present"] = any(
        any(kw in txt for kw in stamp_kw) for txt in text_list
    )

    # Field change notes - look for text on new layers containing change indicators
    field_change_kw = ["FIELD", "CHANGE", "REVISED", "ADDED", "MODIFIED", "NOTE", "SEE NOTE",
                       "AS BUILT", "ACTUAL", "VERIFY", "CONSTRUCTED", "INSTALLED", "RELOCATED"]
    field_change_count = 0
    for txt, layer in zip(text_list, text_layers):
        on_new_layer = any(layer == nl.upper() for nl in new_layers)
        has_change_kw = any(kw in txt for kw in field_change_kw)
        if on_new_layer and (has_change_kw or len(txt) > 5):
            field_change_count += 1
    result["field_change_text_count"] = field_change_count

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/as_built_markup_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export complete. output_exists={result['output_exists']}, "
      f"new_entities={result['new_entity_count']}, "
      f"new_layers={len(result['new_layers_added'])}, "
      f"asbuilt_layer={result['asbuilt_layer_present']}, "
      f"stamp_text={result['asbuilt_stamp_text_present']}")
PYEOF

echo "=== Export Complete ==="
