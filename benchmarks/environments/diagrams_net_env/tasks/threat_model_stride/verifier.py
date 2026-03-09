#!/usr/bin/env python3
"""Verifier for threat_model_stride task.

Scoring (100 points total):
  - File modified after task start:              10 pts
  - Page count >= 2 (threat table page):         15 pts
  - Trust boundary zones >= 2:                   20 pts
  - STRIDE annotations on >= 3 components:       15 pts
  - Risk level color coding applied:             15 pts
  - Threat table page has structured content:    15 pts
  - SVG exported:                                 5 pts
  - PDF exported:                                 5 pts

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


def verify_threat_model_stride(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Export result not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export: {e}"}

    # Independent re-analysis
    independent = {}
    try:
        dtmp = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
        dtmp.close()
        copy_from_env("/home/ga/Diagrams/oauth_threat_model.drawio", dtmp.name)
        independent = _analyze_threat_model(dtmp.name)
    except Exception as e:
        logger.warning(f"Independent analysis failed: {e}")
    finally:
        try:
            os.unlink(dtmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    subscores = {}

    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Diagram not found at /home/ga/Diagrams/oauth_threat_model.drawio"}

    # 1. File modified (10 pts)
    modified = result.get('file_modified_after_start', False) or independent.get('file_modified_after_start', False)
    if modified:
        score += 10
        subscores["modified"] = True
        feedback.append("File modified during task (+10)")
    else:
        subscores["modified"] = False
        feedback.append("File not modified (0)")

    page_count = max(result.get('page_count', 0), independent.get('page_count', 0))
    trust_count = max(result.get('trust_boundary_count', 0), independent.get('trust_boundary_count', 0))
    stride_count = max(result.get('stride_annotations_count', 0), independent.get('stride_annotations_count', 0))
    has_risk_colors = result.get('risk_colors_present', False) or independent.get('risk_colors_present', False)
    has_threat_table = result.get('has_threat_table', False) or independent.get('has_threat_table', False)
    labels_text = independent.get('labels_text', result.get('labels_text', ''))

    # 2. Page count >= 2 (threat table page) (15 pts)
    if page_count >= 2:
        score += 15
        subscores["pages"] = True
        feedback.append(f"Threat enumeration page added (pages={page_count}) (+15)")
    else:
        subscores["pages"] = False
        feedback.append(f"Missing second page for threat table (pages={page_count}, need ≥2) (0)")

    # 3. Trust boundary zones >= 2 (20 pts)
    if trust_count >= 3:
        score += 20
        subscores["trust_boundaries"] = True
        feedback.append(f"All trust zones defined (External/DMZ/Internal, count={trust_count}) (+20)")
    elif trust_count >= 2:
        score += 13
        subscores["trust_boundaries"] = "partial"
        feedback.append(f"Trust boundaries partially defined (count={trust_count}, need ≥3) (+13)")
    elif trust_count >= 1:
        score += 6
        subscores["trust_boundaries"] = "minimal"
        feedback.append(f"Only one trust boundary zone (count={trust_count}) (+6)")
    else:
        subscores["trust_boundaries"] = False
        feedback.append("No trust boundary zones detected (0)")

    # 4. STRIDE annotations on >= 3 components (15 pts)
    if stride_count >= 5:
        score += 15
        subscores["stride_annotations"] = True
        feedback.append(f"STRIDE annotations on {stride_count} components (+15)")
    elif stride_count >= 3:
        score += 10
        subscores["stride_annotations"] = "partial"
        feedback.append(f"STRIDE annotations on {stride_count} components (partial, need ≥5) (+10)")
    elif stride_count >= 1:
        score += 5
        subscores["stride_annotations"] = "minimal"
        feedback.append(f"Minimal STRIDE annotations ({stride_count}) (+5)")
    else:
        # Check via label text
        stride_terms = ["spoofing", "tampering", "repudiation", "disclosure", "denial", "elevation", "stride"]
        if sum(1 for t in stride_terms if t in labels_text) >= 3:
            score += 10
            subscores["stride_annotations"] = "text_detected"
            feedback.append("STRIDE threat categories found in labels (+10)")
        else:
            subscores["stride_annotations"] = False
            feedback.append("No STRIDE threat annotations detected (0)")

    # 5. Risk color coding (15 pts)
    if has_risk_colors:
        score += 15
        subscores["risk_colors"] = True
        feedback.append("Risk level color coding applied (red/orange/green) (+15)")
    else:
        # Check via labels
        if any(kw in labels_text for kw in ["high risk", "medium risk", "low risk", "risk: high", "risk level"]):
            score += 8
            subscores["risk_colors"] = "label_only"
            feedback.append("Risk levels labeled in text (no fill colors) (+8)")
        else:
            subscores["risk_colors"] = False
            feedback.append("Risk level color coding not detected (0)")

    # 6. Threat table structured content (15 pts)
    if has_threat_table:
        score += 15
        subscores["threat_table"] = True
        feedback.append("Threat enumeration table populated on page 2 (+15)")
    else:
        # Partial: threat-related text exists on page 2
        threat_terms = ["t-0", "t-1", "t-2", "threat id", "element", "mitigation", "stride category"]
        if any(t in labels_text for t in threat_terms):
            score += 8
            subscores["threat_table"] = "partial"
            feedback.append("Some threat table content detected on page 2 (+8)")
        else:
            subscores["threat_table"] = False
            feedback.append("No threat enumeration table found on page 2 (0)")

    # 7. SVG exported (5 pts)
    svg_ok = result.get('svg_exported', False)
    if svg_ok:
        score += 5
        subscores["svg"] = True
        feedback.append("SVG exported (+5)")
    else:
        subscores["svg"] = False
        feedback.append("SVG not found at /home/ga/Diagrams/oauth_threat_model.svg (0)")

    # 8. PDF exported (5 pts)
    pdf_ok = result.get('pdf_exported', False)
    if pdf_ok:
        score += 5
        subscores["pdf"] = True
        feedback.append("PDF exported (+5)")
    else:
        subscores["pdf"] = False
        feedback.append("PDF not found at /home/ga/Diagrams/oauth_threat_model.pdf (0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }


def _analyze_threat_model(file_path):
    if not HAS_ET or not os.path.exists(file_path):
        return {}

    def decode_content(text):
        try:
            url_dec = urllib.parse.unquote(text.strip())
            data = base64.b64decode(url_dec + '==')
            return zlib.decompress(data, -15).decode('utf-8')
        except Exception:
            return None

    import re

    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception:
        return {}

    pages = []
    if root.tag == 'mxfile':
        for diag in root.findall('diagram'):
            cells = []
            if diag.text and diag.text.strip():
                xml_str = decode_content(diag.text)
                if xml_str:
                    try:
                        inner_root = ET.fromstring(xml_str)
                        cells = inner_root.findall('.//mxCell')
                    except Exception:
                        pass
            else:
                cells = diag.findall('.//mxCell')
            pages.append((diag.get('name', ''), cells))
    else:
        pages = [('Page-1', root.findall('.//mxCell'))]

    all_labels = []
    all_styles = []
    trust_count = 0
    stride_count = 0

    stride_terms = ["spoofing", "tampering", "repudiation", "information disclosure",
                    "denial of service", "elevation of privilege", "stride"]

    red_fills = ["#ff0000", "#ff3333", "#f8cecc", "#d50000", "#b85450", "ff0000", "f8cecc"]
    orange_fills = ["#ff8000", "#ff9900", "#ffe6cc", "#d79b00", "ffe6cc", "ff9900"]
    green_fills = ["#00cc00", "#009900", "#d5e8d4", "#82b366", "d5e8d4"]

    for page_name, cells in pages:
        for cell in cells:
            cid = cell.get("id", "")
            vertex = cell.get("vertex", "0")
            value = (cell.get("value") or "").strip()
            style = (cell.get("style") or "").lower()

            if vertex == "1" and cid not in ("0", "1"):
                all_labels.append(value.lower())
                all_styles.append(style)

                # Trust boundary: dashed container
                if ("dashed=1" in style or "dashed" in style) and "edge" not in style:
                    trust_count += 1
                if value and any(kw in value.lower() for kw in ["external zone", "dmz", "internal zone", "trust boundary"]):
                    trust_count += 1

                # STRIDE annotations
                if any(t in value.lower() for t in stride_terms):
                    stride_count += 1

    labels_text = " ".join(all_labels)
    styles_text = " ".join(all_styles)

    has_risk_colors = (any(c in styles_text for c in red_fills) and
                       any(c in styles_text for c in green_fills))

    # Threat table: check page 2+
    has_threat_table = False
    if len(pages) >= 2:
        table_labels = []
        for pname, cells in pages[1:]:
            for cell in cells:
                if cell.get("vertex", "0") == "1" and cell.get("id", "") not in ("0", "1"):
                    table_labels.append((cell.get("value") or "").lower())
        table_text = " ".join(table_labels)
        threat_terms2 = ["mitigation", "risk level", "element", "threat id", "t-0", "t-1", "stride"]
        if sum(1 for t in threat_terms2 if t in table_text) >= 2 or len(table_labels) >= 5:
            has_threat_table = True

    return {
        "page_count": len(pages),
        "labels_text": labels_text[:3000],
        "trust_boundary_count": trust_count,
        "stride_annotations_count": stride_count,
        "risk_colors_present": has_risk_colors,
        "has_threat_table": has_threat_table,
        "file_modified_after_start": False,
    }
