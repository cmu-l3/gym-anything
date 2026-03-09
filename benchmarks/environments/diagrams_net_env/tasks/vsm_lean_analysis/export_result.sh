#!/bin/bash
# Export script for vsm_lean_analysis task

echo "=== Exporting VSM Lean Analysis Result ==="

take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output" 2>/dev/null || DISPLAY=:1 import -window root "$output" 2>/dev/null || true
}

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import os
import re
import base64
import zlib
import urllib.parse

TASK_START = int(open("/tmp/task_start_timestamp").read().strip()) if os.path.exists("/tmp/task_start_timestamp") else 0

# Agent may save to either location — check both
DIAGRAM_PATHS = [
    "/home/ga/Diagrams/current_state_vsm.drawio",
    "/home/ga/Desktop/current_state_vsm.drawio",
]
PDF_PATHS = [
    "/home/ga/Diagrams/current_state_vsm.pdf",
    "/home/ga/Desktop/current_state_vsm.pdf",
]

result = {
    "file_exists": False,
    "file_modified_after_start": False,
    "file_path_used": None,
    "page_count": 0,
    "shape_count": 0,
    "edge_count": 0,
    "pdf_exported": False,
    "lean_shapes_count": 0,
    "process_box_count": 0,
    "inventory_triangle_count": 0,
    "has_supplier": False,
    "has_customer": False,
    "has_push_arrows": False,
    "has_timeline": False,
    "kaizen_burst_count": 0,
    "has_kaizen_bursts": False,
    "process_names_found": [],
    "labels_text": "",
}

def decode_drawio_content(encoded_text):
    try:
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded + '==')
        return zlib.decompress(data, -15).decode('utf-8')
    except Exception:
        return None

def get_all_cells(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception:
        return 0, []

    all_cells = []
    if root.tag == 'mxfile':
        diagrams = root.findall('diagram')
        for diag in diagrams:
            if diag.text and diag.text.strip():
                xml_str = decode_drawio_content(diag.text)
                if xml_str:
                    try:
                        inner = ET.fromstring(xml_str)
                        all_cells.extend(inner.findall('.//mxCell'))
                    except Exception:
                        pass
            else:
                all_cells.extend(diag.findall('.//mxCell'))
        return len(diagrams), all_cells
    else:
        return 1, root.findall('.//mxCell')

# Find the VSM diagram file
diagram_path = None
for p in DIAGRAM_PATHS:
    if os.path.exists(p):
        diagram_path = p
        break

if diagram_path:
    result["file_exists"] = True
    result["file_path_used"] = diagram_path
    mtime = os.path.getmtime(diagram_path)
    result["file_modified_after_start"] = int(mtime) > TASK_START

    page_count, all_cells = get_all_cells(diagram_path)
    result["page_count"] = page_count

    shapes = []
    edges = []
    all_labels = []
    all_styles = []
    lean_count = 0
    process_count = 0
    inventory_count = 0
    kaizen_count = 0
    push_count = 0
    timeline_found = False
    supplier_found = False
    customer_found = False

    process_names_expected = ["pc press", "spot weld", "assembly", "weld", "press", "stamping"]

    for cell in all_cells:
        cid = cell.get("id", "")
        vertex = cell.get("vertex", "0")
        edge = cell.get("edge", "0")
        value = (cell.get("value") or "").strip()
        style = (cell.get("style") or "").lower()

        if vertex == "1" and cid not in ("0", "1"):
            shapes.append(value)
            all_labels.append(value.lower())
            all_styles.append(style)

            # Lean mapping shapes
            if "lean_mapping" in style or "lean" in style:
                lean_count += 1

            # Manufacturing process box
            if "manufacturing_process" in style or "lean_mapping.manufacturing" in style:
                process_count += 1
            elif any(kw in style for kw in ["process", "mxgraph.lean"]) and vertex == "1":
                # Generic rectangle that might be a process box
                if any(pn in value.lower() for pn in process_names_expected):
                    process_count += 1

            # Inventory triangle
            if "inventory_triangle" in style or "triangle" in style or "mxgraph.lean_mapping.inventory" in style:
                inventory_count += 1

            # Kaizen burst
            if "kaizen" in style or "kaizen" in value.lower() or "burst" in style or "starburst" in style:
                kaizen_count += 1

            # Supplier
            if any(kw in value.lower() for kw in ["supplier", "steelpro", "raw material", "vendor"]):
                supplier_found = True

            # Customer
            if any(kw in value.lower() for kw in ["customer", "distribution", "demand", "regional"]):
                customer_found = True

            # Timeline
            if any(kw in value.lower() for kw in ["lead time", "timeline", "value-added", "value added", "takt", "c/t", "cycle time total"]):
                timeline_found = True

        if edge == "1":
            edges.append(value)
            val_lower = value.lower()
            style_lower = style.lower()
            # Push arrow
            if "push" in val_lower or "push_arrow" in style_lower or "lean_mapping.push" in style_lower:
                push_count += 1

    result["shape_count"] = len(shapes)
    result["edge_count"] = len(edges)
    result["lean_shapes_count"] = lean_count
    result["process_box_count"] = process_count
    result["inventory_triangle_count"] = inventory_count
    result["kaizen_burst_count"] = kaizen_count
    result["has_kaizen_bursts"] = kaizen_count >= 3
    result["has_supplier"] = supplier_found
    result["has_customer"] = customer_found
    result["has_push_arrows"] = push_count >= 2
    result["has_timeline"] = timeline_found

    labels_text = " ".join(all_labels)
    result["labels_text"] = labels_text[:3000]

    # Check which process names are found
    found_processes = [pn for pn in process_names_expected if pn in labels_text]
    result["process_names_found"] = found_processes

    # Fallback: count processes by label matching if style-based count is 0
    if result["process_box_count"] == 0:
        result["process_box_count"] = len(found_processes)

    # Fallback timeline detection
    if not timeline_found:
        timeline_terms = ["lead", "value", "takt", "wait time", "cycle", "timeline"]
        if sum(1 for t in timeline_terms if t in labels_text) >= 3:
            timeline_found = True
            result["has_timeline"] = True

# Check PDF output
for p in PDF_PATHS:
    if os.path.exists(p):
        result["pdf_exported"] = True
        result["pdf_modified_after_start"] = os.path.getmtime(p) > TASK_START
        break

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
