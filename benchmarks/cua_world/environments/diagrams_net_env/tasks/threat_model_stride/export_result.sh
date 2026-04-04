#!/bin/bash
# Export script for threat_model_stride task

echo "=== Exporting STRIDE Threat Model Result ==="

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
DIAGRAM_PATH = "/home/ga/Diagrams/oauth_threat_model.drawio"
SVG_PATH = "/home/ga/Diagrams/oauth_threat_model.svg"
PDF_PATH = "/home/ga/Diagrams/oauth_threat_model.pdf"

result = {
    "file_exists": False,
    "file_modified_after_start": False,
    "page_count": 0,
    "page_names": [],
    "shape_count": 0,
    "edge_count": 0,
    "svg_exported": False,
    "pdf_exported": False,
    "has_trust_boundaries": False,
    "trust_boundary_count": 0,
    "stride_annotations_count": 0,
    "has_stride_text": False,
    "risk_colors_present": False,
    "has_threat_table": False,
    "labels_text": "",
    "styles_text": "",
}

def decode_drawio_content(encoded_text):
    try:
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded + '==')
        return zlib.decompress(data, -15).decode('utf-8')
    except Exception:
        return None

def get_all_cells_per_page(file_path):
    """Returns list of (page_name, cells_list) per page."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception:
        return []

    pages = []
    if root.tag == 'mxfile':
        for diag in root.findall('diagram'):
            name = diag.get('name', '')
            cells = []
            if diag.text and diag.text.strip():
                xml_str = decode_drawio_content(diag.text)
                if xml_str:
                    try:
                        inner = ET.fromstring(xml_str)
                        cells = inner.findall('.//mxCell')
                    except Exception:
                        pass
            else:
                cells = diag.findall('.//mxCell')
            pages.append((name, cells))
    else:
        pages = [('Page-1', root.findall('.//mxCell'))]
    return pages

if os.path.exists(DIAGRAM_PATH):
    result["file_exists"] = True
    mtime = os.path.getmtime(DIAGRAM_PATH)
    result["file_modified_after_start"] = int(mtime) > TASK_START

    pages = get_all_cells_per_page(DIAGRAM_PATH)
    result["page_count"] = len(pages)
    result["page_names"] = [p[0] for p in pages]

    all_labels = []
    all_styles = []
    trust_boundary_count = 0
    stride_annotation_count = 0

    stride_terms = ["spoofing", "tampering", "repudiation", "information disclosure",
                    "denial of service", "elevation of privilege",
                    " s,", " t,", " r,", " i,", " d,", " e,",
                    "stride", "threat", "s/t/r", "t/r/i"]

    for page_name, cells in pages:
        page_labels = []
        page_styles = []
        for cell in cells:
            cid = cell.get("id", "")
            vertex = cell.get("vertex", "0")
            value = (cell.get("value") or "").strip()
            style = (cell.get("style") or "").lower()

            if vertex == "1" and cid not in ("0", "1"):
                page_labels.append(value.lower())
                page_styles.append(style)

                # Trust boundary: dashed container/rectangle
                if ("dashed=1" in style or "dashed" in style) and ("ellipse" not in style or "container" in style):
                    trust_boundary_count += 1
                # Also check for swimlane-style zones labeled as zones
                if value and any(kw in value.lower() for kw in ["external zone", "dmz", "internal zone", "trust boundary", "untrusted", "trusted zone"]):
                    trust_boundary_count += 1

                # STRIDE annotations
                if any(t in value.lower() for t in stride_terms):
                    stride_annotation_count += 1

        all_labels.extend(page_labels)
        all_styles.extend(page_styles)

    result["shape_count"] = len(all_labels)
    result["trust_boundary_count"] = trust_boundary_count
    result["has_trust_boundaries"] = trust_boundary_count >= 2
    result["stride_annotations_count"] = stride_annotation_count
    result["has_stride_text"] = stride_annotation_count >= 2

    labels_text = " ".join(all_labels)
    result["labels_text"] = labels_text[:3000]

    # Risk color coding: check for red/orange/green fills
    red_fills = ["#ff0000", "#ff3333", "#f8cecc", "#d50000", "#b85450", "red"]
    orange_fills = ["#ff8000", "#ff9900", "#ffe6cc", "#d79b00", "orange"]
    green_fills = ["#00cc00", "#009900", "#d5e8d4", "#82b366", "#00aa00", "green"]

    styles_str = " ".join(all_styles).lower()
    has_red = any(c in styles_str for c in red_fills)
    has_orange = any(c in styles_str for c in orange_fills)
    has_green = any(c in styles_str for c in green_fills)
    result["risk_colors_present"] = has_red or (has_orange and has_green)

    # Threat table on page 2: look for tabular structure (many rows with threat content)
    if len(pages) >= 2:
        table_page_cells = []
        for pname, cells in pages[1:]:  # pages after first
            table_page_cells.extend(cells)

        table_values = [(cell.get("value") or "") for cell in table_page_cells
                        if cell.get("vertex","0") == "1" and cell.get("id","") not in ("0","1")]
        threat_id_count = sum(1 for v in table_values if re.search(r't[-_]?\d+', v.lower()))
        stride_count = sum(1 for v in table_values
                          if any(kw in v.lower() for kw in stride_terms + ["mitigation", "risk level", "element"]))
        result["has_threat_table"] = len(table_values) >= 5 or threat_id_count >= 2 or stride_count >= 3

if os.path.exists(SVG_PATH):
    result["svg_exported"] = True
    result["svg_modified_after_start"] = int(os.path.getmtime(SVG_PATH)) > TASK_START

if os.path.exists(PDF_PATH):
    result["pdf_exported"] = True
    result["pdf_modified_after_start"] = int(os.path.getmtime(PDF_PATH)) > TASK_START

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
