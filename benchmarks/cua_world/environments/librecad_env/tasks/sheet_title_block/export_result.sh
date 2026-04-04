#!/bin/bash
echo "=== Exporting sheet_title_block result ==="

pkill -f librecad 2>/dev/null || true
sleep 3

DISPLAY=:1 import -window root /tmp/sheet_title_block_end.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, sys

OUTPUT_FILE = "/home/ga/Documents/LibreCAD/floorplan_sheet.dxf"
BASELINE_FILE = "/tmp/sheet_title_block_baseline.json"
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
    "text_layers": [],
    "new_layers_added": [],
    "title_block_border_layer_present": False,
    "title_info_layer_present": False,
    "seal_layer_present": False,
    "revision_layer_present": False,
    "new_line_count": 0,
    "new_text_count": 0,
    "has_project_info_text": False,
    "has_drawing_number_text": False,
    "has_scale_text": False,
    "has_seal_or_approval_text": False,
    "has_revision_text": False,
    "parse_error": None,
}

if not os.path.isfile(OUTPUT_FILE):
    with open("/tmp/sheet_title_block_result.json", "w") as f:
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

    # Identify title block layers
    border_kw = ["BORDER", "TB-BORDER", "TITLE-BORDER", "FRAME", "SHEET", "TB", "TITLEBLOCK", "TITLE_BLOCK"]
    info_kw = ["INFO", "TB-INFO", "TITLE-INFO", "PROJECT", "TB-TITLE", "TITLE", "HEADING", "TB-TEXT"]
    seal_kw = ["SEAL", "STAMP", "CERTIF", "APPROVAL", "TB-SEAL", "ARCHITECT", "ENGINEER", "REVIEW"]
    rev_kw = ["REVISION", "REV", "TB-REV", "CHANGE", "HISTORY"]

    result["title_block_border_layer_present"] = any(any(kw in l for kw in border_kw) for l in new_upper)
    result["title_info_layer_present"] = any(any(kw in l for kw in info_kw) for l in new_upper)
    result["seal_layer_present"] = any(any(kw in l for kw in seal_kw) for l in new_upper)
    result["revision_layer_present"] = any(any(kw in l for kw in rev_kw) for l in new_upper)

    # Entity counts
    counts = Counter(e.dxftype() for e in entities)
    result["entity_counts"] = dict(counts)
    result["total_entities"] = len(entities)
    result["new_entity_count"] = max(0, len(entities) - baseline.get("entity_count", 967))

    # Count new line entities (on new layers)
    new_line_count = 0
    new_text_count = 0
    text_list = []
    text_layers = []

    for e in entities:
        try:
            layer = e.dxf.layer.upper()
            on_new = any(layer == nl.upper() for nl in new_layers)
            if on_new:
                if e.dxftype() == "LINE":
                    new_line_count += 1
                elif e.dxftype() == "LWPOLYLINE":
                    new_line_count += 1
                elif e.dxftype() in ("TEXT", "MTEXT"):
                    new_text_count += 1
            if e.dxftype() == "TEXT":
                txt = e.dxf.text.strip().upper()
                if txt:
                    text_list.append(txt)
                    text_layers.append(layer)
            elif e.dxftype() == "MTEXT":
                txt = e.text.strip().upper()
                if txt:
                    text_list.append(txt)
                    text_layers.append(layer)
        except Exception:
            pass

    result["new_line_count"] = new_line_count
    result["new_text_count"] = new_text_count
    result["text_content"] = text_list[:150]
    result["text_layers"] = text_layers[:150]

    # Check text content for required information types
    project_kw = ["PROJECT", "ADDRESS", "OWNER", "CLIENT", "BUILDING", "GARAGE", "RESIDENCE", "PROPERTY",
                  "LOCATION", "SITE", "PERMIT", "SUBJECT"]
    drawing_kw = ["DRAWING", "SHEET", "DWG", "DWG NO", "SHEET NO", "A-", "G-", "SHEET 1", "PAGE"]
    scale_kw = ["SCALE", "1:", "1/4", "3/16", "1/8", "NTS", "AS NOTED", "1 IN"]
    seal_text_kw = ["SEAL", "STAMP", "REVIEW", "PERMIT", "CERTIF", "ARCHITECT", "ENGINEER",
                    "LICENSED", "FOR PERMIT", "FOR CONSTRUCTION", "PRELIMINARY", "APPROVAL"]
    rev_text_kw = ["REV", "REVISION", "REVISED", "DATE", "DESCRIPTION", "CHANGE", "BY", "APPROVED"]

    combined_text = " ".join(text_list)
    result["has_project_info_text"] = any(kw in combined_text for kw in project_kw)
    result["has_drawing_number_text"] = any(kw in combined_text for kw in drawing_kw)
    result["has_scale_text"] = any(kw in combined_text for kw in scale_kw)
    result["has_seal_or_approval_text"] = any(kw in combined_text for kw in seal_text_kw)
    result["has_revision_text"] = any(kw in combined_text for kw in rev_text_kw)

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/sheet_title_block_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export complete. output_exists={result['output_exists']}, "
      f"new_entities={result['new_entity_count']}, new_lines={result['new_line_count']}, "
      f"new_text={result['new_text_count']}, border_layer={result['title_block_border_layer_present']}")
PYEOF

echo "=== Export Complete ==="
