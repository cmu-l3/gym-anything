#!/usr/bin/env python3
"""Verifier for c4_architecture_model task.

Case: eShopOnContainers C4 Architecture Model
Source: Microsoft eShopOnContainers open-source reference application
        https://github.com/dotnet-architecture/eShopOnContainers

Scoring (100 points total):
  - File created and newer than task start:           10 pts
  - Page count == 3 (Context + Container + Legend):   15 pts
  - System Context page: >= 6 shapes:                 15 pts
  - Container Diagram page: >= 10 shapes:             20 pts
  - eShopOnContainers system name appears:             5 pts
  - C4 color coding (blue for owned system):          10 pts
  - Labeled relationship edges (>= 5):                 10 pts
  - PDF exported:                                     15 pts

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

EXPECTED_SERVICES = ["catalog", "basket", "ordering", "identity", "payment", "marketing",
                     "location", "gateway", "eventbus", "rabbitmq", "frontend", "mobile"]
EXPECTED_EXTERNAL = ["stripe", "sendgrid", "azure", "rabbitmq", "application insights"]


def verify_c4_architecture_model(traj, env_info, task_info):
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
    for path in ["/home/ga/Diagrams/ecommerce_c4_model.drawio",
                 "/home/ga/Desktop/ecommerce_c4_model.drawio"]:
        try:
            dtmp = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
            dtmp.close()
            copy_from_env(path, dtmp.name)
            independent = _analyze_c4(dtmp.name)
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
                "feedback": "C4 diagram not found — save as ~/Diagrams/ecommerce_c4_model.drawio"}

    # 1. File created during task (10 pts)
    modified = result.get('file_modified_after_start', False) or independent.get('file_modified_after_start', False)
    if modified:
        score += 10
        subscores["file_created"] = True
        feedback.append("C4 diagram created during task (+10)")
    else:
        subscores["file_created"] = False
        feedback.append("File not created/modified during task (0)")

    # Merge best values
    page_count = max(result.get('page_count', 0), independent.get('page_count', 0))
    context_shapes = max(result.get('context_page_shape_count', 0), independent.get('context_shapes', 0))
    container_shapes = max(result.get('container_page_shape_count', 0), independent.get('container_shapes', 0))
    has_legend = result.get('has_legend_page', False) or independent.get('has_legend_page', False)
    has_c4_blue = result.get('has_c4_blue', False) or independent.get('has_c4_blue', False)
    labeled_edges = max(result.get('labeled_edges_count', 0), independent.get('labeled_edges_count', 0))
    eshop = result.get('eshop_mentioned', False) or independent.get('eshop_mentioned', False)
    labels_text = independent.get('labels_text', result.get('labels_text', ''))
    services_found = independent.get('microservices_found', result.get('microservices_mentioned', []))
    external_found = independent.get('external_found', result.get('external_systems_mentioned', []))

    # 2. Page count == 3 (15 pts)
    if page_count >= 3:
        score += 15
        subscores["pages"] = True
        feedback.append(f"All 3 C4 pages present (pages={page_count}) (+15)")
    elif page_count == 2:
        score += 9
        subscores["pages"] = "partial"
        feedback.append(f"Only 2 pages (need 3: Context+Container+Legend) (+9)")
    elif page_count == 1:
        score += 4
        subscores["pages"] = "minimal"
        feedback.append(f"Only 1 page (need 3) (+4)")
    else:
        subscores["pages"] = False
        feedback.append("No pages found (0)")

    # 3. System Context page >= 6 shapes (15 pts)
    if context_shapes >= 6:
        score += 15
        subscores["context_page"] = True
        feedback.append(f"System Context page adequate (shapes={context_shapes}) (+15)")
    elif context_shapes >= 4:
        score += 9
        subscores["context_page"] = "partial"
        feedback.append(f"Context page partial (shapes={context_shapes}, need ≥6) (+9)")
    elif context_shapes >= 2:
        score += 5
        subscores["context_page"] = "minimal"
        feedback.append(f"Context page minimal (shapes={context_shapes}) (+5)")
    else:
        subscores["context_page"] = False
        feedback.append(f"System Context page insufficient (shapes={context_shapes}, need ≥6) (0)")

    # 4. Container Diagram page >= 10 shapes (20 pts)
    if container_shapes >= 10:
        score += 20
        subscores["container_page"] = True
        feedback.append(f"Container Diagram page adequate (shapes={container_shapes}) (+20)")
    elif container_shapes >= 7:
        score += 14
        subscores["container_page"] = "partial"
        feedback.append(f"Container page partial (shapes={container_shapes}, need ≥10) (+14)")
    elif container_shapes >= 4:
        score += 8
        subscores["container_page"] = "minimal"
        feedback.append(f"Container page minimal (shapes={container_shapes}) (+8)")
    else:
        # Fall back to total shape count if page classification failed
        total_shapes = result.get('shape_count', 0) or independent.get('total_shapes', 0)
        if total_shapes >= 15:
            score += 10
            subscores["container_page"] = "total_count_fallback"
            feedback.append(f"Total shape count sufficient ({total_shapes} across all pages) (+10)")
        else:
            subscores["container_page"] = False
            feedback.append(f"Container page insufficient (shapes={container_shapes}, need ≥10) (0)")

    # 5. eShopOnContainers system name mentioned (5 pts)
    eshop_in_labels = any(kw in labels_text for kw in ["eshoponcontainers", "eshop", "eshop on containers"])
    if eshop or eshop_in_labels:
        score += 5
        subscores["system_name"] = True
        feedback.append("eShopOnContainers system name present (+5)")
    else:
        subscores["system_name"] = False
        feedback.append("eShopOnContainers system name not found in diagram (0)")

    # 6. C4 color coding (10 pts)
    if has_c4_blue:
        score += 10
        subscores["c4_colors"] = True
        feedback.append("C4 color conventions applied (+10)")
    else:
        # Check if any system-owned elements use blue tones
        if any(c in labels_text for c in ["#1168", "#0050", "blue", "azure"]):
            score += 5
            subscores["c4_colors"] = "partial"
            feedback.append("Partial C4 color coding (+5)")
        else:
            subscores["c4_colors"] = False
            feedback.append("C4 color conventions not detected (0)")

    # 7. Labeled relationship edges >= 5 (10 pts)
    if labeled_edges >= 5:
        score += 10
        subscores["labeled_edges"] = True
        feedback.append(f"Relationship edges labeled with protocols (count={labeled_edges}) (+10)")
    elif labeled_edges >= 2:
        score += 5
        subscores["labeled_edges"] = "partial"
        feedback.append(f"Some edges labeled (count={labeled_edges}, need ≥5) (+5)")
    else:
        subscores["labeled_edges"] = False
        feedback.append(f"Insufficient labeled relationship edges (count={labeled_edges}, need ≥5) (0)")

    # 8. PDF exported (15 pts)
    pdf_ok = result.get('pdf_exported', False) and result.get('pdf_modified_after_start', True)
    if pdf_ok:
        score += 15
        subscores["pdf"] = True
        feedback.append("PDF exported (+15)")
    else:
        subscores["pdf"] = False
        feedback.append("PDF not found at ~/Diagrams/ecommerce_c4_model.pdf (0)")

    # Bonus info for feedback
    if services_found:
        feedback.append(f"[INFO] Services found: {', '.join(services_found[:5])}")
    if external_found:
        feedback.append(f"[INFO] External systems: {', '.join(external_found)}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }


def _analyze_c4(file_path):
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

    pages_data = []
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
            pages_data.append((diag.get('name', ''), cells))
    else:
        pages_data = [('Page-1', root.findall('.//mxCell'))]

    all_labels = []
    all_styles = []
    labeled_edges = 0
    total_shapes = 0

    context_shapes = 0
    container_shapes = 0
    has_legend_page = False

    c4_blue_variants = ["1168bd", "0050ef", "2196f3", "1565c0", "dae8fc"]

    for i, (page_name, cells) in enumerate(pages_data):
        page_name_lower = page_name.lower()
        shape_count_page = 0

        for cell in cells:
            cid = cell.get("id", "")
            vertex = cell.get("vertex", "0")
            edge = cell.get("edge", "0")
            value = (cell.get("value") or "").strip()
            style = (cell.get("style") or "").lower()

            if vertex == "1" and cid not in ("0", "1") and value:
                all_labels.append(value.lower())
                all_styles.append(style)
                shape_count_page += 1
                total_shapes += 1

            if edge == "1" and value and value.strip():
                labeled_edges += 1

        if any(kw in page_name_lower for kw in ["context", "level 1", "l1"]):
            context_shapes = shape_count_page
        elif any(kw in page_name_lower for kw in ["container", "level 2", "l2"]):
            container_shapes = shape_count_page
        elif any(kw in page_name_lower for kw in ["legend", "key"]):
            has_legend_page = True

        if i == 0 and context_shapes == 0:
            context_shapes = shape_count_page
        elif i == 1 and container_shapes == 0:
            container_shapes = shape_count_page
        elif i >= 2 and not has_legend_page:
            has_legend_page = True

    labels_text = " ".join(all_labels)
    styles_text = " ".join(all_styles)

    has_c4_blue = any(c in styles_text for c in c4_blue_variants)
    eshop = any(kw in labels_text for kw in ["eshoponcontainers", "eshop", "eshop on containers"])

    microservices_found = [s for s in EXPECTED_SERVICES if s in labels_text]
    external_found = [s for s in EXPECTED_EXTERNAL if s in labels_text]

    return {
        "page_count": len(pages_data),
        "context_shapes": context_shapes,
        "container_shapes": container_shapes,
        "total_shapes": total_shapes,
        "has_legend_page": has_legend_page,
        "labeled_edges_count": labeled_edges,
        "has_c4_blue": has_c4_blue,
        "eshop_mentioned": eshop,
        "microservices_found": microservices_found,
        "external_found": external_found,
        "labels_text": labels_text[:4000],
        "file_modified_after_start": False,
    }
