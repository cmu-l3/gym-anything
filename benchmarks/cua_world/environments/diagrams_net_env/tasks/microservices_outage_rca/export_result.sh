#!/bin/bash
echo "=== Collecting results for microservices_outage_rca ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Read task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Run Python analysis
python3 << 'PYEOF'
import json
import os
import sys
import re
import base64
import zlib
from xml.etree import ElementTree as ET

DRAWIO_PATH = "/home/ga/Diagrams/shopstream_architecture.drawio"
PDF_PATH = "/home/ga/Diagrams/shopstream_rca.pdf"

def read_task_start():
    try:
        with open("/tmp/task_start_timestamp") as f:
            return int(f.read().strip())
    except:
        return 0

def decode_diagram_xml(diagram_el):
    """Decode a <diagram> element, handling both compressed and plain XML."""
    text = (diagram_el.text or "").strip()
    if not text:
        # Try to find mxGraphModel directly as child
        gm = diagram_el.find(".//mxGraphModel")
        if gm is not None:
            return ET.tostring(gm, encoding="unicode")
        return ""
    # Try base64 + deflate (compressed format)
    try:
        raw = base64.b64decode(text)
        xml_bytes = zlib.decompress(raw, -15)
        return xml_bytes.decode("utf-8")
    except:
        pass
    # Try plain base64
    try:
        return base64.b64decode(text).decode("utf-8")
    except:
        pass
    # Assume plain XML text
    return text

def parse_drawio(path):
    """Parse a .drawio file, returning cells from all pages."""
    result = {
        "pages": [],
        "all_cells": [],
        "shape_count": 0,
        "edge_count": 0,
        "page_count": 0
    }
    try:
        tree = ET.parse(path)
        root = tree.getroot()
        diagrams = root.findall(".//diagram")
        result["page_count"] = len(diagrams)

        for diag in diagrams:
            page_name = diag.get("name", "")
            page_id = diag.get("id", "")

            # Decode page content
            xml_content = decode_diagram_xml(diag)
            if not xml_content:
                result["pages"].append({"name": page_name, "id": page_id, "cells": []})
                continue

            # Parse cells from this page
            try:
                if "<mxGraphModel" in xml_content:
                    page_root = ET.fromstring(xml_content)
                else:
                    page_root = ET.fromstring("<wrapper>" + xml_content + "</wrapper>")
            except:
                result["pages"].append({"name": page_name, "id": page_id, "cells": []})
                continue

            cells = []
            for cell in page_root.iter("mxCell"):
                cell_data = {
                    "id": cell.get("id", ""),
                    "value": cell.get("value", ""),
                    "style": cell.get("style", ""),
                    "vertex": cell.get("vertex", "0"),
                    "edge": cell.get("edge", "0"),
                    "source": cell.get("source", ""),
                    "target": cell.get("target", ""),
                    "parent": cell.get("parent", "")
                }
                # Get geometry if present
                geom = cell.find("mxGeometry")
                if geom is not None:
                    cell_data["x"] = geom.get("x", "")
                    cell_data["y"] = geom.get("y", "")
                    cell_data["width"] = geom.get("width", "")
                    cell_data["height"] = geom.get("height", "")
                cells.append(cell_data)
                result["all_cells"].append(cell_data)

            result["pages"].append({"name": page_name, "id": page_id, "cells": cells})

        result["shape_count"] = sum(1 for c in result["all_cells"] if c["vertex"] == "1" and c.get("width"))
        result["edge_count"] = sum(1 for c in result["all_cells"] if c["edge"] == "1")

    except Exception as e:
        result["parse_error"] = str(e)

    return result

def extract_fill_colors(cells):
    """Extract fill colors from cell styles, keyed by cell value (label text)."""
    colors = {}
    for c in cells:
        val = re.sub(r'<[^>]+>', '', c.get("value", "")).strip().lower()
        style = c.get("style", "")
        fill_match = re.search(r'fillColor=(#[0-9a-fA-F]{6})', style)
        if fill_match and val:
            colors[val] = fill_match.group(1).lower()
    return colors

def detect_root_cause_label(cells):
    """Check if any cell contains 'ROOT CAUSE' text."""
    for c in cells:
        val = re.sub(r'<[^>]+>', '', c.get("value", "")).strip()
        if "root cause" in val.lower():
            return True, val
    return False, ""

def detect_dashed_red_edges(cells):
    """Count edges that are dashed and red-colored (propagation arrows)."""
    count = 0
    edges = []
    for c in cells:
        if c.get("edge") != "1":
            continue
        style = c.get("style", "")
        is_dashed = "dashed=1" in style or "dashPattern" in style
        is_red = any(color in style.lower() for color in ["#ff0000", "#cc0000", "#ff3333", "#e06666", "red"])
        if is_dashed and is_red:
            count += 1
            edges.append({
                "source": c.get("source", ""),
                "target": c.get("target", ""),
                "value": re.sub(r'<[^>]+>', '', c.get("value", "")).strip()
            })
    return count, edges

def detect_circuit_breakers(cells):
    """Count cells mentioning circuit breaker."""
    count = 0
    for c in cells:
        val = re.sub(r'<[^>]+>', '', c.get("value", "")).strip().lower()
        if "circuit" in val and "breaker" in val:
            count += 1
    return count

def detect_async_remediation(cells):
    """Check page 2+ for async/queue remediation annotations."""
    count = 0
    for c in cells:
        val = re.sub(r'<[^>]+>', '', c.get("value", "")).strip().lower()
        if any(term in val for term in ["async", "message queue", "rabbitmq", "event-driven", "queue"]):
            count += 1
    return count

# ---- Main ----
task_start = read_task_start()

result = {
    "task_start": task_start,
    "drawio_exists": os.path.isfile(DRAWIO_PATH),
    "pdf_exists": os.path.isfile(PDF_PATH),
    "file_modified": False,
    "parsed_data": None,
    "fill_colors": {},
    "root_cause_found": False,
    "root_cause_text": "",
    "dashed_red_edge_count": 0,
    "dashed_red_edges": [],
    "page_count": 0,
    "page_names": [],
    "circuit_breaker_count": 0,
    "async_remediation_count": 0,
    "screenshot_path": "/tmp/task_final.png"
}

if result["drawio_exists"]:
    mtime = int(os.path.getmtime(DRAWIO_PATH))
    result["file_modified"] = mtime > task_start
    result["file_mtime"] = mtime

    parsed = parse_drawio(DRAWIO_PATH)
    result["page_count"] = parsed["page_count"]
    result["page_names"] = [p["name"] for p in parsed["pages"]]
    result["shape_count"] = parsed["shape_count"]
    result["edge_count"] = parsed["edge_count"]

    # Analyze page 1 (architecture with annotations)
    if parsed["pages"]:
        page1_cells = parsed["pages"][0].get("cells", [])
        result["fill_colors"] = extract_fill_colors(page1_cells)
        result["root_cause_found"], result["root_cause_text"] = detect_root_cause_label(page1_cells)
        result["dashed_red_edge_count"], result["dashed_red_edges"] = detect_dashed_red_edges(page1_cells)

    # Analyze page 2+ (remediation)
    if len(parsed["pages"]) > 1:
        page2_cells = parsed["pages"][1].get("cells", [])
        result["circuit_breaker_count"] = detect_circuit_breakers(page2_cells)
        result["async_remediation_count"] = detect_async_remediation(page2_cells)

    # Also check across ALL pages for these annotations
    all_cells = parsed["all_cells"]
    rc_found_all, rc_text_all = detect_root_cause_label(all_cells)
    if not result["root_cause_found"] and rc_found_all:
        result["root_cause_found"] = rc_found_all
        result["root_cause_text"] = rc_text_all

    dre_count_all, dre_all = detect_dashed_red_edges(all_cells)
    if dre_count_all > result["dashed_red_edge_count"]:
        result["dashed_red_edge_count"] = dre_count_all
        result["dashed_red_edges"] = dre_all

    cb_all = detect_circuit_breakers(all_cells)
    if cb_all > result["circuit_breaker_count"]:
        result["circuit_breaker_count"] = cb_all

    async_all = detect_async_remediation(all_cells)
    if async_all > result["async_remediation_count"]:
        result["async_remediation_count"] = async_all

if result["pdf_exists"]:
    pdf_mtime = int(os.path.getmtime(PDF_PATH))
    result["pdf_mtime"] = pdf_mtime
    result["pdf_size"] = os.path.getsize(PDF_PATH)
    result["pdf_created_during_task"] = pdf_mtime > task_start

# Write result
output_path = "/tmp/task_result.json"
try:
    with open(output_path, "w") as f:
        json.dump(result, f, indent=2)
    os.chmod(output_path, 0o666)
    print(f"Result written to {output_path}")
except Exception as e:
    # Fallback
    fallback = json.dumps(result)
    with open(output_path, "w") as f:
        f.write(fallback)
    os.chmod(output_path, 0o666)
    print(f"Result written (fallback) to {output_path}: {e}")

PYEOF

echo "=== Export complete ==="
