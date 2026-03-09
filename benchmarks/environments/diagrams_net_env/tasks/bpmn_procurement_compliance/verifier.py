#!/usr/bin/env python3
"""Verifier for bpmn_procurement_compliance task.

Scoring (100 points total):
  - File modified after task start:               10 pts
  - Swimlane/lane count >= 3:                     20 pts
  - Exclusive (XOR) gateway present:              15 pts
  - Labeled gateway exit flows (>=2 labeled):     15 pts
  - Named start event:                            10 pts
  - Rejection path present:                       10 pts
  - PDF exported:                                 10 pts
  - PNG exported:                                 10 pts

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


def verify_bpmn_procurement_compliance(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": "Export result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export: {e}"}

    # Independent re-analysis
    independent = {}
    try:
        dtmp = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
        dtmp.close()
        copy_from_env("/home/ga/Diagrams/procurement_process.drawio", dtmp.name)
        independent = _analyze_bpmn(dtmp.name)
    except Exception as e:
        logger.warning(f"Independent BPMN analysis failed: {e}")
    finally:
        try:
            os.unlink(dtmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    subscores = {}

    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Diagram file not found at /home/ga/Diagrams/procurement_process.drawio"}

    # 1. File modified (10 pts)
    modified = result.get('file_modified_after_start', False) or independent.get('file_modified_after_start', False)
    if modified:
        score += 10
        subscores["modified"] = True
        feedback.append("File modified during task (+10)")
    else:
        subscores["modified"] = False
        feedback.append("File not modified (0)")

    # Merge counts from both sources (use lane_count only; swimlane_count includes pool containers)
    lane_count = max(result.get('lane_count', 0), independent.get('lane_count', 0))
    labels_text = independent.get('labels_text', result.get('labels_text', ''))
    styles_text = independent.get('styles_text', result.get('styles_text', ''))
    labeled_flows = max(result.get('labeled_gateway_flows', 0), independent.get('labeled_edge_count', 0))

    # 2. Swimlane lanes >= 3 (20 pts — was 1 lane originally, needs 3+)
    if lane_count >= 4:
        score += 20
        subscores["swimlanes"] = True
        feedback.append(f"All required swimlane lanes present (count={lane_count}) (+20)")
    elif lane_count >= 3:
        score += 14
        subscores["swimlanes"] = "partial"
        feedback.append(f"Most swimlane lanes present (count={lane_count}, need ≥4) (+14)")
    elif lane_count >= 2:
        score += 7
        subscores["swimlanes"] = "minimal"
        feedback.append(f"Some swimlane lanes added (count={lane_count}, need ≥4) (+7)")
    else:
        subscores["swimlanes"] = False
        feedback.append(f"Swimlane lanes not adequately added (count={lane_count}, need ≥3) (0)")

    # 3. Exclusive (XOR) gateway (15 pts)
    has_xor = result.get('has_exclusive_gateway', False) or independent.get('has_exclusive_gateway', False)
    has_xor_by_label = any(kw in labels_text for kw in ["exclusivegw", "xor"])
    if has_xor or has_xor_by_label:
        score += 15
        subscores["exclusive_gateway"] = True
        feedback.append("Exclusive (XOR) gateway corrected (+15)")
    else:
        subscores["exclusive_gateway"] = False
        feedback.append("Gateway type not corrected to exclusive (XOR) (0)")

    # 4. Labeled gateway flows >= 2 (15 pts)
    import re as _re2
    approval_terms_re = [r"\bapproved\b", r"\byes\b", r"\bno\b", r"\brejected\b", r"\bdenied\b", r"\bdeclined\b", r"not approved"]
    labeled_by_content = sum(1 for t in approval_terms_re if _re2.search(t, labels_text))
    if labeled_flows >= 2 or labeled_by_content >= 2:
        score += 15
        subscores["labeled_flows"] = True
        feedback.append("Gateway exit flows labeled (Approved/Rejected) (+15)")
    elif labeled_flows >= 1 or labeled_by_content >= 1:
        score += 7
        subscores["labeled_flows"] = "partial"
        feedback.append(f"Only partial gateway flow labeling (+7)")
    else:
        subscores["labeled_flows"] = False
        feedback.append("Gateway exit flows not labeled (0)")

    # 5. Named start event (10 pts)
    has_named_start = result.get('has_named_start', False) or independent.get('has_named_start', False)
    if has_named_start:
        score += 10
        subscores["named_start"] = True
        feedback.append("Start event is named (+10)")
    else:
        subscores["named_start"] = False
        feedback.append("Start event still unnamed (0)")

    # 6. Rejection/notification path (10 pts)
    has_rejection = result.get('has_rejection_path', False) or independent.get('has_rejection_path', False)
    if has_rejection:
        score += 10
        subscores["rejection_path"] = True
        feedback.append("Rejection notification path present (+10)")
    else:
        subscores["rejection_path"] = False
        feedback.append("No rejection/deny path found (0)")

    # 7. PDF exported (10 pts)
    pdf_ok = result.get('pdf_exported', False) and result.get('pdf_modified_after_start', True)
    if pdf_ok:
        score += 10
        subscores["pdf"] = True
        feedback.append("PDF exported (+10)")
    else:
        subscores["pdf"] = False
        feedback.append("PDF not found at /home/ga/Diagrams/procurement_process.pdf (0)")

    # 8. PNG exported (10 pts)
    png_ok = result.get('png_exported', False) and result.get('png_modified_after_start', True)
    if png_ok:
        score += 10
        subscores["png"] = True
        feedback.append("PNG exported (+10)")
    else:
        subscores["png"] = False
        feedback.append("PNG not found at /home/ga/Diagrams/procurement_process.png (0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }


def _analyze_bpmn(file_path):
    if not HAS_ET or not os.path.exists(file_path):
        return {}

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
    if root.tag == 'mxfile':
        for diag in root.findall('diagram'):
            if diag.text and diag.text.strip():
                xml_str = decode_content(diag.text)
                if xml_str:
                    try:
                        inner = ET.parse(None) if False else None
                        inner_root = ET.fromstring(xml_str)
                        all_cells.extend(inner_root.findall('.//mxCell'))
                    except Exception:
                        pass
            else:
                all_cells.extend(diag.findall('.//mxCell'))
    else:
        all_cells = root.findall('.//mxCell')

    labels = []
    styles = []
    lane_count = 0
    swimlane_count = 0
    labeled_edge_count = 0
    has_named_start = False
    has_exclusive_gateway = False
    has_rejection_path = False

    for cell in all_cells:
        cid = cell.get("id", "")
        vertex = cell.get("vertex", "0")
        edge = cell.get("edge", "0")
        value = (cell.get("value") or "").strip()
        style = (cell.get("style") or "").lower()

        if vertex == "1" and cid not in ("0", "1"):
            labels.append(value.lower())
            styles.append(style)
            if "swimlane" in style:
                swimlane_count += 1
                if "startsize" in style:
                    lane_count += 1
            if "exclusivegw" in style or "xor" in style:
                has_exclusive_gateway = True
            if "symbol=start" in style and value:
                has_named_start = True

        if edge == "1" and value:
            labeled_edge_count += 1

    labels_text = " ".join(labels)
    import re as _re
    rejection_terms = [r"\breject", r"\bdeclined\b", r"\bdenied\b", r"\bno\b", r"not approved"]
    has_rejection_path = any(_re.search(t, labels_text) for t in rejection_terms)

    return {
        "labels_text": labels_text[:3000],
        "styles_text": " ".join(styles)[:2000],
        "swimlane_count": swimlane_count,
        "lane_count": lane_count,
        "labeled_edge_count": labeled_edge_count,
        "has_exclusive_gateway": has_exclusive_gateway,
        "has_named_start": has_named_start,
        "has_rejection_path": has_rejection_path,
        "file_modified_after_start": False,
    }
