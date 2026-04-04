#!/bin/bash
# Export script for c4_architecture_model task

echo "=== Exporting C4 Architecture Model Result ==="

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

DIAGRAM_PATHS = [
    "/home/ga/Diagrams/ecommerce_c4_model.drawio",
    "/home/ga/Desktop/ecommerce_c4_model.drawio",
]
PDF_PATHS = [
    "/home/ga/Diagrams/ecommerce_c4_model.pdf",
    "/home/ga/Desktop/ecommerce_c4_model.pdf",
]

result = {
    "file_exists": False,
    "file_modified_after_start": False,
    "file_path_used": None,
    "page_count": 0,
    "page_names": [],
    "pdf_exported": False,
    "context_page_shape_count": 0,
    "container_page_shape_count": 0,
    "legend_page_shape_count": 0,
    "has_system_context_page": False,
    "has_container_page": False,
    "has_legend_page": False,
    "has_c4_blue": False,
    "has_c4_grey": False,
    "labeled_edges_count": 0,
    "shopflow_mentioned": False,
    "microservices_mentioned": [],
    "external_systems_mentioned": [],
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

def get_pages(file_path):
    """Returns list of (page_name, cells_list)."""
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

# Find the C4 diagram file
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

    pages = get_pages(diagram_path)
    result["page_count"] = len(pages)
    result["page_names"] = [p[0] for p in pages]

    def count_shapes(cells):
        return sum(1 for c in cells
                   if c.get("vertex","0")=="1" and c.get("id","") not in ("0","1")
                   and (c.get("value") or "").strip())

    def get_labels(cells):
        return [((c.get("value") or "") + " " + (c.get("style") or "")).lower()
                for c in cells if c.get("vertex","0")=="1" and c.get("id","") not in ("0","1")]

    def get_edge_labels(cells):
        return [(c.get("value") or "").lower() for c in cells
                if c.get("edge","0")=="1" and (c.get("value") or "").strip()]

    all_labels = []
    all_styles_text = []
    labeled_edges = 0

    for i, (page_name, cells) in enumerate(pages):
        page_shape_count = count_shapes(cells)
        page_labels = get_labels(cells)
        edge_labels = get_edge_labels(cells)
        labeled_edges += len(edge_labels)
        all_labels.extend(page_labels)

        page_name_lower = page_name.lower()

        # Classify pages by name
        if any(kw in page_name_lower for kw in ["context", "level 1", "l1", "system context"]):
            result["context_page_shape_count"] = page_shape_count
            result["has_system_context_page"] = True
        elif any(kw in page_name_lower for kw in ["container", "level 2", "l2"]):
            result["container_page_shape_count"] = page_shape_count
            result["has_container_page"] = True
        elif any(kw in page_name_lower for kw in ["legend", "key", "notation"]):
            result["legend_page_shape_count"] = page_shape_count
            result["has_legend_page"] = True
        else:
            # Classify by index if no name match
            if i == 0 and page_shape_count > 0:
                result["context_page_shape_count"] = page_shape_count
                result["has_system_context_page"] = True
            elif i == 1 and page_shape_count > 0:
                result["container_page_shape_count"] = page_shape_count
                result["has_container_page"] = True
            elif i == 2 and page_shape_count > 0:
                result["legend_page_shape_count"] = page_shape_count
                result["has_legend_page"] = True

        # Collect styles for color check
        for cell in cells:
            style = (cell.get("style") or "").lower()
            all_styles_text.append(style)

    result["labeled_edges_count"] = labeled_edges

    labels_text = " ".join(all_labels)
    styles_text = " ".join(all_styles_text)
    result["labels_text"] = labels_text[:4000]
    result["styles_text"] = styles_text[:2000]

    # eShopOnContainers system name mentioned
    result["shopflow_mentioned"] = any(kw in labels_text for kw in ["eshoponcontainers", "eshop"])

    # C4 color coding
    c4_blue_variants = ["1168bd", "1168BD", "#1168", "0050ef", "2196f3", "1565c0"]
    c4_grey_variants = ["#999", "#808080", "#666666", "#888888", "grey", "gray"]
    result["has_c4_blue"] = any(c.lower() in styles_text for c in c4_blue_variants) or \
                            "dae8fc" in styles_text or "b0c4de" in styles_text or \
                            any("blue" in lbl for lbl in all_labels if "system" in lbl or "service" in lbl)
    result["has_c4_grey"] = any(c in styles_text for c in c4_grey_variants) or \
                            "f5f5f5" in styles_text or "f0f0f0" in styles_text

    # Check which microservices/systems are mentioned
    expected_services = ["catalog", "basket", "ordering", "identity", "payment", "marketing",
                         "location", "gateway", "eventbus", "rabbitmq", "frontend", "mobile"]
    result["microservices_mentioned"] = [s for s in expected_services if s in labels_text]

    expected_external = ["stripe", "sendgrid", "azure", "rabbitmq", "application insights"]
    result["external_systems_mentioned"] = [s for s in expected_external if s in labels_text]

# Check PDF
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
