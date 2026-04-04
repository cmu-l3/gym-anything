#!/usr/bin/env python3
"""Verifier for network_topology_multi_layer task.

Scoring (100 points total):
  - File modified after task start:          10 pts
  - Page count >= 2 (OOB management page):   15 pts
  - Shape count >= 20 (all 3 new layers):    15 pts
  - Edge count >= 16 (interconnected layers): 10 pts
  - Core layer labels present:               15 pts
  - Distribution layer labels present:       10 pts
  - Access layer labels present:             10 pts
  - Bandwidth/protocol edge labels:          10 pts
  - Color coding (>=3 distinct fill colors):  5 pts
  - PDF exported:                            10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import base64
import zlib
import urllib.parse

try:
    import xml.etree.ElementTree as ET
    HAS_ET = True
except ImportError:
    HAS_ET = False

logger = logging.getLogger(__name__)


def verify_network_topology_multi_layer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Export result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}

    # Independent re-analysis of the diagram file
    independent_result = {}
    try:
        drawio_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
        drawio_tmp.close()
        copy_from_env("/home/ga/Diagrams/enterprise_network.drawio", drawio_tmp.name)
        independent_result = _analyze_drawio(drawio_tmp.name)
    except Exception as e:
        logger.warning(f"Independent diagram analysis failed: {e}")
    finally:
        try:
            os.unlink(drawio_tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    subscores = {}

    # Gate: file must exist
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Diagram file not found at /home/ga/Diagrams/enterprise_network.drawio"}

    # 1. File modified after task start (10 pts)
    modified = result.get('file_modified_after_start', False) or independent_result.get('file_modified_after_start', False)
    if modified:
        score += 10
        subscores["file_modified"] = True
        feedback.append("File modified during task (+10)")
    else:
        subscores["file_modified"] = False
        feedback.append("File not modified after task start (0)")

    # Use independent result for shape/edge/page counts if available
    page_count = independent_result.get('page_count', result.get('page_count', 0))
    shape_count = independent_result.get('shape_count', result.get('shape_count', 0))
    edge_count = independent_result.get('edge_count', result.get('edge_count', 0))
    labels_text = independent_result.get('labels_text', result.get('labels_text', ''))
    styles_text = independent_result.get('styles_text', result.get('styles_text', ''))
    has_oob = result.get('has_oob_page', False) or (page_count >= 2)

    # 2. Page count >= 2 (OOB management page) (15 pts)
    if page_count >= 2:
        score += 15
        subscores["multi_page"] = True
        feedback.append(f"OOB management page added (pages={page_count}) (+15)")
    else:
        subscores["multi_page"] = False
        feedback.append(f"Missing second diagram page for OOB management (pages={page_count}, need ≥2) (0)")

    # 3. Shape count >= 20 (all layers) (15 pts)
    # Starting file has ~5 shapes; need ≥20 means 15+ added
    if shape_count >= 20:
        score += 15
        subscores["shape_count"] = True
        feedback.append(f"Sufficient shapes for all layers (count={shape_count}) (+15)")
    elif shape_count >= 12:
        score += 8
        subscores["shape_count"] = "partial"
        feedback.append(f"Partial layers added (shapes={shape_count}, need ≥20) (+8)")
    else:
        subscores["shape_count"] = False
        feedback.append(f"Insufficient shapes — only {shape_count} shapes, need ≥20 (0)")

    # 4. Edge count >= 16 (interconnected) (10 pts)
    if edge_count >= 16:
        score += 10
        subscores["edge_count"] = True
        feedback.append(f"Well-connected topology (edges={edge_count}) (+10)")
    elif edge_count >= 8:
        score += 5
        subscores["edge_count"] = "partial"
        feedback.append(f"Partially connected (edges={edge_count}, need ≥16) (+5)")
    else:
        subscores["edge_count"] = False
        feedback.append(f"Too few connections (edges={edge_count}) (0)")

    # 5. Core layer labels (15 pts)
    core_terms = ["core", "nexus", "core-sw", "core_sw", "core switch"]
    has_core = any(t in labels_text.lower() for t in core_terms)
    if has_core:
        score += 15
        subscores["core_layer"] = True
        feedback.append("Core switching layer detected (+15)")
    else:
        subscores["core_layer"] = False
        feedback.append("Core switching layer not found in diagram (0)")

    # 6. Distribution layer labels (10 pts)
    dist_terms = ["dist", "distribution", "catalyst 9500", "dist-sw", "dist_sw"]
    has_dist = any(t in labels_text.lower() for t in dist_terms)
    if has_dist:
        score += 10
        subscores["dist_layer"] = True
        feedback.append("Distribution layer detected (+10)")
    else:
        subscores["dist_layer"] = False
        feedback.append("Distribution layer not found (0)")

    # 7. Access layer labels (10 pts)
    access_terms = ["access", "access-sw", "access_sw", "floor", "2960", "wiring closet"]
    has_access = any(t in labels_text.lower() for t in access_terms)
    if has_access:
        score += 10
        subscores["access_layer"] = True
        feedback.append("Access layer detected (+10)")
    else:
        subscores["access_layer"] = False
        feedback.append("Access layer not found (0)")

    # 8. Bandwidth/protocol edge labels (10 pts)
    bw_check = result.get('has_bandwidth_labels', False)
    bw_terms = ["gbps", "mbps", "ospf", "1g", "10g", "40g", "bandwidth"]
    edge_labels = result.get('edge_labels', [])
    edge_label_text = " ".join(edge_labels).lower()
    has_bw = bw_check or any(t in edge_label_text for t in bw_terms) or any(t in labels_text for t in bw_terms)
    if has_bw:
        score += 10
        subscores["bandwidth_labels"] = True
        feedback.append("Bandwidth/protocol labels on links (+10)")
    else:
        subscores["bandwidth_labels"] = False
        feedback.append("Missing bandwidth/protocol labels on inter-layer links (0)")

    # 9. Color coding >= 3 distinct fill colors (5 pts)
    distinct_colors = result.get('distinct_fill_colors', 0) or independent_result.get('distinct_fill_colors', 0)
    if distinct_colors >= 3 or result.get('has_color_coding', False):
        score += 5
        subscores["color_coding"] = True
        feedback.append(f"Layer color coding applied ({distinct_colors} distinct colors) (+5)")
    else:
        subscores["color_coding"] = False
        feedback.append("Layer color coding not detected (0)")

    # 10. PDF exported (10 pts)
    pdf_ok = result.get('pdf_exported', False) and result.get('pdf_modified_after_start', False)
    if pdf_ok:
        score += 10
        subscores["pdf_exported"] = True
        feedback.append("PDF exported successfully (+10)")
    else:
        subscores["pdf_exported"] = False
        feedback.append("PDF not found at /home/ga/Diagrams/enterprise_network.pdf (0)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }


def _analyze_drawio(file_path):
    """Independent analysis of a draw.io file."""
    if not HAS_ET or not os.path.exists(file_path):
        return {}

    import re

    def decode_content(text):
        try:
            url_dec = urllib.parse.unquote(text.strip())
            data = base64.b64decode(url_dec + '==')
            return zlib.decompress(data, -15).decode('utf-8')
        except Exception:
            return None

    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception:
        return {}

    all_cells = []
    page_count = 0
    page_names = []

    if root.tag == 'mxfile':
        diagrams = root.findall('diagram')
        page_count = len(diagrams)
        for diag in diagrams:
            page_names.append(diag.get('name', ''))
            if diag.text and diag.text.strip():
                xml_str = decode_content(diag.text)
                if xml_str:
                    try:
                        inner = ET.fromstring(xml_str)
                        all_cells.extend(inner.findall('.//mxCell'))
                    except Exception:
                        pass
            else:
                all_cells.extend(diag.findall('.//mxCell'))
    else:
        page_count = 1
        all_cells = root.findall('.//mxCell')

    shapes = []
    edges = []
    all_labels = []
    all_styles = []
    color_fills = set()

    for cell in all_cells:
        cid = cell.get("id", "")
        vertex = cell.get("vertex", "0")
        edge = cell.get("edge", "0")
        value = (cell.get("value") or "").strip()
        style = (cell.get("style") or "").lower()

        if vertex == "1" and cid not in ("0", "1") and value:
            shapes.append(value)
            all_labels.append(value.lower())
            all_styles.append(style)
            m = re.search(r'fillcolor=#([0-9a-fA-F]{6})', style, re.IGNORECASE)
            if m:
                color_fills.add(m.group(1).lower())

        if edge == "1":
            edges.append(value)

    return {
        "page_count": page_count,
        "shape_count": len(shapes),
        "edge_count": len(edges),
        "labels_text": " ".join(all_labels)[:3000],
        "styles_text": " ".join(all_styles)[:2000],
        "distinct_fill_colors": len(color_fills),
        "file_modified_after_start": False,  # mtime not available in independent analysis
    }
