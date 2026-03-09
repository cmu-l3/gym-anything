#!/bin/bash
# Export script for bpmn_procurement_compliance task

echo "=== Exporting BPMN Procurement Compliance Result ==="

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
DIAGRAM_PATH = "/home/ga/Diagrams/procurement_process.drawio"
PDF_PATH = "/home/ga/Diagrams/procurement_process.pdf"
PNG_PATH = "/home/ga/Diagrams/procurement_process.png"

result = {
    "file_exists": False,
    "file_modified_after_start": False,
    "page_count": 0,
    "shape_count": 0,
    "edge_count": 0,
    "pdf_exported": False,
    "png_exported": False,
    "swimlane_count": 0,
    "lane_count": 0,
    "bpmn_shape_types": [],
    "labeled_gateway_flows": 0,
    "has_exclusive_gateway": False,
    "has_named_start": False,
    "has_rejection_path": False,
    "has_send_task": False,
    "has_data_objects": False,
    "labels_text": "",
}

def decode_drawio_content(encoded_text):
    try:
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded + '==')
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception:
        return None

def get_all_cells(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception:
        return 0, [], []

    all_cells = []
    page_names = []

    if root.tag == 'mxfile':
        diagrams = root.findall('diagram')
        for diag in diagrams:
            page_names.append(diag.get('name', ''))
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
        return len(diagrams), all_cells, page_names
    else:
        return 1, root.findall('.//mxCell'), ['Page-1']

if os.path.exists(DIAGRAM_PATH):
    result["file_exists"] = True
    mtime = os.path.getmtime(DIAGRAM_PATH)
    result["file_modified_after_start"] = int(mtime) > TASK_START

    page_count, all_cells, page_names = get_all_cells(DIAGRAM_PATH)
    result["page_count"] = page_count

    shapes = []
    edges = []
    all_labels = []
    swimlane_count = 0
    lane_count = 0
    bpmn_types = set()
    labeled_edge_count = 0

    for cell in all_cells:
        cid = cell.get("id", "")
        vertex = cell.get("vertex", "0")
        edge = cell.get("edge", "0")
        value = (cell.get("value") or "").strip()
        style = (cell.get("style") or "").lower()

        if vertex == "1" and cid not in ("0", "1"):
            shapes.append(value)
            all_labels.append(value.lower())

            # Detect swimlane containers
            if "swimlane" in style or "pool" in style:
                swimlane_count += 1
            if "swimlane" in style and "startsize" in style:
                lane_count += 1

            # BPMN shape type detection
            if "mxgraph.bpmn" in style:
                m = re.search(r'symbol=([a-zA-Z_]+)', style)
                if m:
                    bpmn_types.add(m.group(1))
                # Also check perimeter for task/gateway
                if "rectangleperimeter" in style and "task" in style:
                    bpmn_types.add("task")
                if "rhombusperimeter" in style:
                    bpmn_types.add("gateway")
                if "ellipseperimeter" in style:
                    bpmn_types.add("event")

        if edge == "1":
            edges.append(value)
            if value and len(value.strip()) > 0:
                labeled_edge_count += 1

    result["shape_count"] = len(shapes)
    result["edge_count"] = len(edges)
    result["swimlane_count"] = swimlane_count
    result["lane_count"] = lane_count
    result["bpmn_shape_types"] = list(bpmn_types)
    result["labeled_gateway_flows"] = labeled_edge_count

    labels_text = " ".join(all_labels)
    result["labels_text"] = labels_text[:3000]

    # Check for exclusive gateway (XOR)
    styles_text = " ".join((cell.get("style") or "").lower() for cell in all_cells)
    result["has_exclusive_gateway"] = any(t in styles_text for t in ["exclusivegw", "xor", "exclusive"])

    # Named start event: start event WITH a non-empty value
    for cell in all_cells:
        style = (cell.get("style") or "").lower()
        value = (cell.get("value") or "").strip()
        if "symbol=start" in style and value:
            result["has_named_start"] = True

    # Rejection path: look for "reject" or "decline" or "no" in labels
    rejection_terms = ["reject", "decline", "denied", "not approved", "no", "refused"]
    result["has_rejection_path"] = any(t in labels_text for t in rejection_terms)

    # Send task: BPMN send task style
    result["has_send_task"] = "send" in styles_text or "message" in labels_text

    # Data objects: data object style in BPMN
    result["has_data_objects"] = any(
        "dataobject" in (cell.get("style") or "").lower() or
        "data object" in (cell.get("value") or "").lower() or
        "purchase order" in (cell.get("value") or "").lower() or
        "invoice" in (cell.get("value") or "").lower()
        for cell in all_cells
        if cell.get("vertex", "0") == "1"
    )

if os.path.exists(PDF_PATH):
    result["pdf_exported"] = True
    result["pdf_modified_after_start"] = int(os.path.getmtime(PDF_PATH)) > TASK_START

if os.path.exists(PNG_PATH):
    result["png_exported"] = True
    result["png_modified_after_start"] = int(os.path.getmtime(PNG_PATH)) > TASK_START

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
