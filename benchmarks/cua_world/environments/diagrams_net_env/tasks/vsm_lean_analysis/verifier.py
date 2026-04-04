#!/usr/bin/env python3
"""Verifier for vsm_lean_analysis task.

Case: Toyota Steering Bracket current-state VSM
Source: Rother & Shook (1998) "Learning to See", Lean Enterprise Institute

Scoring (100 points total):
  - File created and newer than task start:       10 pts
  - Process boxes >= 5 (all 5 production steps):  25 pts
  - Inventory triangles >= 5 (between steps):     15 pts
  - Supplier and Customer icons present:          15 pts
  - Timeline/lead time section present:           15 pts
  - Kaizen burst annotations >= 3:               10 pts
  - PDF exported:                                 10 pts

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

PROCESS_NAMES = ["pc press", "spot weld", "assembly", "weld", "press", "stamping"]


def verify_vsm_lean_analysis(traj, env_info, task_info):
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

    # Independent re-analysis — try both possible paths
    independent = {}
    for path in ["/home/ga/Diagrams/current_state_vsm.drawio",
                 "/home/ga/Desktop/current_state_vsm.drawio"]:
        try:
            dtmp = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
            dtmp.close()
            copy_from_env(path, dtmp.name)
            independent = _analyze_vsm(dtmp.name)
            break
        except Exception:
            pass
        finally:
            try:
                os.unlink(dtmp.name)
            except Exception:
                pass

    score = 0
    feedback = []
    subscores = {}

    if not result.get('file_exists'):
        return {"passed": False, "score": 0,
                "feedback": "VSM diagram not found — save as ~/Diagrams/current_state_vsm.drawio"}

    # 1. File created and newer than start (10 pts)
    modified = result.get('file_modified_after_start', False) or independent.get('file_modified_after_start', False)
    if modified:
        score += 10
        subscores["file_created"] = True
        feedback.append("VSM file created during task (+10)")
    else:
        subscores["file_created"] = False
        feedback.append("File not created/modified during task (0)")

    # Merge best counts from both sources
    shape_count = max(result.get('shape_count', 0), independent.get('shape_count', 0))
    process_count = max(result.get('process_box_count', 0), independent.get('process_box_count', 0))
    inventory_count = max(result.get('inventory_triangle_count', 0), independent.get('inventory_triangle_count', 0))
    kaizen_count = max(result.get('kaizen_burst_count', 0), independent.get('kaizen_burst_count', 0))
    has_supplier = result.get('has_supplier', False) or independent.get('has_supplier', False)
    has_customer = result.get('has_customer', False) or independent.get('has_customer', False)
    has_timeline = result.get('has_timeline', False) or independent.get('has_timeline', False)
    labels_text = independent.get('labels_text', result.get('labels_text', ''))
    process_names_found = independent.get('process_names_found', result.get('process_names_found', []))

    # Cross-check: count process names in labels if process_count is 0
    if process_count == 0:
        process_count = len(process_names_found)
    if process_count == 0 and shape_count >= 5:
        # Large shape count without detected process labels — give partial benefit of doubt
        process_count = min(shape_count // 3, 5)

    # 2. Process boxes >= 5 (25 pts) — 5 steps in Toyota steering bracket case
    if process_count >= 5:
        score += 25
        subscores["process_boxes"] = True
        feedback.append(f"All 5 process boxes present (count={process_count}) (+25)")
    elif process_count >= 4:
        score += 18
        subscores["process_boxes"] = "partial"
        feedback.append(f"4 of 5 process boxes present (count={process_count}) (+18)")
    elif process_count >= 3:
        score += 10
        subscores["process_boxes"] = "minimal"
        feedback.append(f"Some process boxes present (count={process_count}) (+10)")
    else:
        subscores["process_boxes"] = False
        feedback.append(f"Insufficient process boxes (count={process_count}, need 5) (0)")

    # 3. Inventory triangles >= 5 (between all 5 steps + coil + FG) (15 pts)
    if inventory_count >= 5:
        score += 15
        subscores["inventory_triangles"] = True
        feedback.append(f"All inventory triangles present (count={inventory_count}) (+15)")
    elif inventory_count >= 3:
        score += 8
        subscores["inventory_triangles"] = "partial"
        feedback.append(f"Some inventory triangles (count={inventory_count}, need 5) (+8)")
    elif inventory_count >= 1:
        score += 4
        subscores["inventory_triangles"] = "minimal"
        feedback.append(f"Few inventory triangles (count={inventory_count}) (+4)")
    else:
        # Check via label text — Toyota WIP numbers: 4600, 4700, 1100, 1600, 1200
        toyota_wip = [4600, 4700, 1100, 1600, 1200]
        if "wip" in labels_text or "inventory" in labels_text or any(str(n) in labels_text for n in toyota_wip):
            score += 5
            subscores["inventory_triangles"] = "label_only"
            feedback.append("WIP/inventory data found in labels but no triangle shapes (+5)")
        else:
            subscores["inventory_triangles"] = False
            feedback.append("No inventory triangles detected (0)")

    # 4. Supplier and Customer present (15 pts)
    if has_supplier and has_customer:
        score += 15
        subscores["supplier_customer"] = True
        feedback.append("Both Supplier and Customer icons present (+15)")
    elif has_supplier or has_customer:
        score += 7
        subscores["supplier_customer"] = "partial"
        feedback.append("Only one of Supplier/Customer present (+7)")
    else:
        # Check by label text — Toyota case: supplier=Michigan Steel Coils, customer=Toyota/Saturn
        if "supplier" in labels_text or "michigan" in labels_text or "steel coil" in labels_text or "acme" in labels_text:
            has_supplier = True
        if "customer" in labels_text or "toyota" in labels_text or "saturn" in labels_text or "distribution" in labels_text:
            has_customer = True
        if has_supplier and has_customer:
            score += 15
            subscores["supplier_customer"] = True
            feedback.append("Supplier and Customer found in labels (+15)")
        elif has_supplier or has_customer:
            score += 7
            subscores["supplier_customer"] = "partial"
            feedback.append("Partial supplier/customer labeling (+7)")
        else:
            subscores["supplier_customer"] = False
            feedback.append("Supplier and Customer icons not found (0)")

    # 5. Timeline/lead time section (15 pts)
    timeline_terms = ["lead time", "total lead", "value-added", "value added", "timeline", "takt"]
    has_timeline_by_label = any(t in labels_text for t in timeline_terms)
    if has_timeline or has_timeline_by_label:
        score += 15
        subscores["timeline"] = True
        feedback.append("Lead time timeline section present (+15)")
    else:
        subscores["timeline"] = False
        feedback.append("No timeline/lead time section found at bottom of VSM (0)")

    # 6. Kaizen bursts >= 3 (10 pts)
    if kaizen_count >= 3:
        score += 10
        subscores["kaizen_bursts"] = True
        feedback.append(f"Kaizen bursts on waste steps (count={kaizen_count}) (+10)")
    elif kaizen_count >= 1:
        score += 5
        subscores["kaizen_bursts"] = "partial"
        feedback.append(f"Some kaizen bursts (count={kaizen_count}, need ≥3) (+5)")
    else:
        if "kaizen" in labels_text:
            score += 5
            subscores["kaizen_bursts"] = "text_only"
            feedback.append("Kaizen mentioned in labels but no burst shapes (+5)")
        else:
            subscores["kaizen_bursts"] = False
            feedback.append("No kaizen burst annotations (0)")

    # 7. PDF exported (10 pts)
    pdf_ok = result.get('pdf_exported', False) and result.get('pdf_modified_after_start', True)
    if pdf_ok:
        score += 10
        subscores["pdf"] = True
        feedback.append("PDF exported (+10)")
    else:
        subscores["pdf"] = False
        feedback.append("PDF not found at ~/Diagrams/current_state_vsm.pdf (0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }


def _analyze_vsm(file_path):
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
                        inner_root = ET.fromstring(xml_str)
                        all_cells.extend(inner_root.findall('.//mxCell'))
                    except Exception:
                        pass
            else:
                all_cells.extend(diag.findall('.//mxCell'))
    else:
        all_cells = root.findall('.//mxCell')

    all_labels = []
    all_styles = []
    process_count = 0
    inventory_count = 0
    kaizen_count = 0
    supplier_found = False
    customer_found = False
    timeline_found = False

    for cell in all_cells:
        cid = cell.get("id", "")
        vertex = cell.get("vertex", "0")
        edge = cell.get("edge", "0")
        value = (cell.get("value") or "").strip()
        style = (cell.get("style") or "").lower()

        if vertex == "1" and cid not in ("0", "1"):
            all_labels.append(value.lower())
            all_styles.append(style)

            if "lean_mapping.manufacturing_process" in style or "manufacturing_process" in style:
                process_count += 1
            elif any(pn in value.lower() for pn in PROCESS_NAMES):
                process_count += 1

            if "inventory_triangle" in style or "lean_mapping.inventory" in style or \
               ("triangle" in style and "lean" in style):
                inventory_count += 1

            if "kaizen" in style or "kaizen" in value.lower() or "starburst" in style:
                kaizen_count += 1

            if any(kw in value.lower() for kw in ["supplier", "michigan", "steel coil", "acme", "raw material"]):
                supplier_found = True
            if any(kw in value.lower() for kw in ["customer", "toyota", "saturn", "distribution", "demand"]):
                customer_found = True
            if any(kw in value.lower() for kw in ["lead time", "value-added", "value added", "timeline", "takt"]):
                timeline_found = True

        if edge == "1":
            style_lower = style
            val_lower = value.lower()
            if "push" in val_lower or "lean_mapping.push" in style_lower:
                pass  # count push arrows

    labels_text = " ".join(all_labels)
    found_processes = [pn for pn in PROCESS_NAMES if pn in labels_text]

    # Fallback timeline detection
    if not timeline_found:
        tl_terms = ["lead", "value", "wait", "cycle", "takt", "nva", "va"]
        if sum(1 for t in tl_terms if t in labels_text) >= 3:
            timeline_found = True

    return {
        "shape_count": len(all_labels),
        "process_box_count": process_count,
        "inventory_triangle_count": inventory_count,
        "kaizen_burst_count": kaizen_count,
        "has_supplier": supplier_found,
        "has_customer": customer_found,
        "has_timeline": timeline_found,
        "labels_text": labels_text[:3000],
        "process_names_found": found_processes,
        "file_modified_after_start": False,
    }
