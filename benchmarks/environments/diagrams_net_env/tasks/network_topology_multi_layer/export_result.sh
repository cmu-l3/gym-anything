#!/bin/bash
# Export script for network_topology_multi_layer task

echo "=== Exporting Network Topology Multi-Layer Result ==="

take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output" 2>/dev/null || DISPLAY=:1 import -window root "$output" 2>/dev/null || true
}

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import os
import base64
import zlib
import urllib.parse

TASK_START = int(open("/tmp/task_start_timestamp").read().strip()) if os.path.exists("/tmp/task_start_timestamp") else 0
DIAGRAM_PATH = "/home/ga/Diagrams/enterprise_network.drawio"
PDF_PATH = "/home/ga/Diagrams/enterprise_network.pdf"

result = {
    "file_exists": False,
    "file_modified_after_start": False,
    "page_count": 0,
    "shape_count": 0,
    "edge_count": 0,
    "labels_text": "",
    "styles_text": "",
    "page_names": [],
    "has_oob_page": False,
    "pdf_exported": False,
    "pdf_modified_after_start": False,
    "has_core_layer": False,
    "has_distribution_layer": False,
    "has_access_layer": False,
    "has_bandwidth_labels": False,
    "has_color_coding": False,
    "edge_labels": [],
}

def decode_drawio_content(encoded_text):
    """Decode draw.io compressed diagram content (URLencode + Base64 + raw deflate)."""
    try:
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded + '==')
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception:
        return None

def get_all_cells(file_path):
    """Parse draw.io file and return (page_count, all_cells, page_names)."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception as e:
        return 0, [], []

    all_cells = []
    page_names = []

    if root.tag == 'mxfile':
        diagrams = root.findall('diagram')
        for diag in diagrams:
            name = diag.get('name', '')
            page_names.append(name)
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
            else:
                all_cells.extend(diag.findall('.//mxCell'))
        return len(diagrams), all_cells, page_names
    else:
        return 1, root.findall('.//mxCell'), ['Page-1']

if os.path.exists(DIAGRAM_PATH):
    result["file_exists"] = True
    mtime = os.path.getmtime(DIAGRAM_PATH)
    result["file_mtime"] = mtime
    result["file_modified_after_start"] = int(mtime) > TASK_START

    page_count, all_cells, page_names = get_all_cells(DIAGRAM_PATH)
    result["page_count"] = page_count
    result["page_names"] = page_names

    # Check for OOB management page
    for name in page_names:
        if any(kw in name.lower() for kw in ["oob", "management", "out-of-band", "mgmt"]):
            result["has_oob_page"] = True

    shapes = []
    edges = []
    all_labels = []
    all_styles = []
    edge_labels = []

    for cell in all_cells:
        cid = cell.get("id", "")
        vertex = cell.get("vertex", "0")
        edge = cell.get("edge", "0")
        value = cell.get("value", "")
        style = cell.get("style", "")

        if vertex == "1" and cid not in ("0", "1") and value and value.strip():
            shapes.append(value)
            all_labels.append(value.lower())
            all_styles.append(style.lower())

        if edge == "1":
            edges.append(value)
            if value and value.strip():
                edge_labels.append(value.lower())

    result["shape_count"] = len(shapes)
    result["edge_count"] = len(edges)
    result["edge_labels"] = edge_labels[:50]

    labels_combined = " ".join(all_labels)
    styles_combined = " ".join(all_styles)
    result["labels_text"] = labels_combined[:3000]
    result["styles_text"] = styles_combined[:3000]

    # Layer detection in labels
    core_terms = ["core", "core-sw", "nexus 9508", "nexus9508", "core switch", "core_sw"]
    dist_terms = ["dist", "distribution", "catalyst 9500", "dist-sw", "dist_sw", "distribution sw"]
    access_terms = ["access", "access-sw", "access_sw", "2960", "catalyst 2960", "floor"]

    result["has_core_layer"] = any(t in labels_combined for t in core_terms)
    result["has_distribution_layer"] = any(t in labels_combined for t in dist_terms)
    result["has_access_layer"] = any(t in labels_combined for t in access_terms)

    # Bandwidth labels on edges
    bw_terms = ["gbps", "mbps", "1g", "10g", "40g", "bandwidth", "ospf", "bw"]
    result["has_bandwidth_labels"] = any(any(t in el for t in bw_terms) for el in edge_labels)

    # Color coding: check for multiple distinct fill colors in styles
    color_fills = set()
    import re
    for style in all_styles:
        m = re.search(r'fillcolor=#([0-9a-fA-F]{6})', style)
        if m:
            color_fills.add(m.group(1).lower())
    result["distinct_fill_colors"] = len(color_fills)
    result["has_color_coding"] = len(color_fills) >= 3  # WAN + Core + Dist + Access = 4 colors expected

if os.path.exists(PDF_PATH):
    result["pdf_exported"] = True
    pdf_mtime = os.path.getmtime(PDF_PATH)
    result["pdf_mtime"] = pdf_mtime
    result["pdf_modified_after_start"] = int(pdf_mtime) > TASK_START

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
