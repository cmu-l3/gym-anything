#!/usr/bin/env python3
"""
Verifier for robot_arm_link_drawings task.

Scoring (100 points total, pass >= 70):
  - FCStd file (bracket_drawing.FCStd) exists:         10 pts
  - FCStd modified after task start:                    10 pts
  - Has TechDraw::DrawPage object:                      20 pts
  - Has >= 2 projection views (DrawViewPart/ProjItem):  15 pts
  - Has >= 3 projection views (bonus):                  10 pts
  - Has >= 3 dimension annotations:                     20 pts
  - PDF file exported (> 5000 bytes):                   15 pts
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# TechDraw object types that represent projection views
VIEW_TYPES = {
    'TechDraw::DrawViewPart',
    'TechDraw::DrawProjGroupItem',
    'TechDraw::DrawViewSection',
}

DIMENSION_TYPES = {
    'TechDraw::DrawViewDimension',
}


def _parse_fcstd(fcstd_path):
    """Parse FCStd ZIP and return (obj_types list, root element)."""
    try:
        with zipfile.ZipFile(fcstd_path, 'r') as z:
            if 'Document.xml' not in z.namelist():
                return None, None
            with z.open('Document.xml') as f:
                root = ET.parse(f).getroot()
        obj_types = [o.get('type', '') for o in root.findall('.//Objects/Object')]
        return obj_types, root
    except Exception as e:
        logger.warning(f"FCStd parse error: {e}")
        return None, None


def verify_robot_arm_link_drawings(traj, env_info, task_info):
    """Verify engineering drawing package creation for T8 bracket."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []

    # ---- Step 1: Load result JSON (timestamps) ----
    result_meta = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
            json_local = tf.name
        copy_from_env('/tmp/robot_arm_link_drawings_result.json', json_local)
        with open(json_local, 'r') as f:
            result_meta = json.load(f)
        os.unlink(json_local)
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")

    task_start = int(result_meta.get('task_start', 0))

    # ---- Step 2: Copy and parse FCStd ----
    obj_types = None
    doc_root = None
    fcstd_mtime = int(result_meta.get('fcstd_mtime', 0))
    fcstd_size = int(result_meta.get('fcstd_size', 0))
    fcstd_exists_meta = result_meta.get('fcstd_exists', False)

    if fcstd_exists_meta:
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd') as tf:
                fcstd_local = tf.name
            copy_from_env('/home/ga/Documents/FreeCAD/bracket_drawing.FCStd', fcstd_local)
            obj_types, doc_root = _parse_fcstd(fcstd_local)
        except Exception as e:
            logger.warning(f"Could not copy/parse bracket_drawing.FCStd: {e}")
        finally:
            if 'fcstd_local' in dir() and os.path.exists(fcstd_local):
                try:
                    os.unlink(fcstd_local)
                except Exception:
                    pass

    # Criterion 1: FCStd exists and valid
    if obj_types is not None:
        score += 10
        feedback_parts.append("bracket_drawing.FCStd exists and is valid")
    else:
        feedback_parts.append("bracket_drawing.FCStd missing or invalid")
        # Check PDF only
        pdf_exists = result_meta.get('pdf_exists', False)
        pdf_size = int(result_meta.get('pdf_size', 0))
        if pdf_exists and pdf_size > 5000:
            score += 15
            feedback_parts.append(f"PDF exported ({pdf_size} bytes) — but no FCStd")
        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Modified after task start
    if task_start > 0 and fcstd_mtime > 0 and int(fcstd_mtime) > int(task_start):
        score += 10
        feedback_parts.append("FCStd modified after task start")
    elif task_start == 0 and fcstd_size > 5000:
        score += 5
        feedback_parts.append("FCStd timestamp not available (partial credit for non-trivial file)")
    else:
        feedback_parts.append("FCStd does not appear to have been modified this session")

    # Criterion 3: TechDraw page
    has_draw_page = any('TechDraw::DrawPage' in t for t in obj_types)
    if has_draw_page:
        score += 20
        feedback_parts.append("TechDraw drawing page created")
    else:
        feedback_parts.append("No TechDraw::DrawPage found — no engineering drawing created")

    # Criterion 4 & 5: Projection views
    n_views = sum(1 for t in obj_types if t in VIEW_TYPES)
    # Also count DrawProjGroup as implying at least one view
    has_proj_group = any('TechDraw::DrawProjGroup' in t for t in obj_types)

    if n_views >= 3 or (has_proj_group and n_views >= 1):
        # DrawProjGroup typically contains 3+ views as DrawProjGroupItem
        score += 15 + 10  # Both criteria
        feedback_parts.append(f"Has {n_views} projection views (front/side/top)")
    elif n_views >= 2:
        score += 15
        feedback_parts.append(f"Has {n_views} projection views (need >= 3 for full credit)")
    elif n_views >= 1 or has_proj_group:
        score += 5
        feedback_parts.append(f"Has {n_views} projection view(s) — need >= 3")
    else:
        feedback_parts.append("No projection views found in drawing")

    # Criterion 6: Dimension annotations
    n_dims = sum(1 for t in obj_types if t in DIMENSION_TYPES)
    if n_dims >= 6:
        score += 20
        feedback_parts.append(f"Has {n_dims} dimension annotations (excellent)")
    elif n_dims >= 3:
        score += 20
        feedback_parts.append(f"Has {n_dims} dimension annotations")
    elif n_dims >= 1:
        score += 8
        feedback_parts.append(f"Has {n_dims} dimension annotation(s) — need >= 3 for full credit")
    else:
        feedback_parts.append("No dimension annotations found")

    # Criterion 7: PDF exported
    pdf_exists = result_meta.get('pdf_exists', False)
    pdf_size = int(result_meta.get('pdf_size', 0))
    pdf_mtime = int(result_meta.get('pdf_mtime', 0))

    if pdf_exists and pdf_size > 5000:
        score += 15
        feedback_parts.append(f"PDF exported successfully ({pdf_size} bytes)")
    elif pdf_exists and pdf_size > 0:
        score += 5
        feedback_parts.append(f"PDF exported but very small ({pdf_size} bytes)")
    else:
        feedback_parts.append("No PDF export found at /home/ga/Documents/FreeCAD/bracket_drawing.pdf")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": {
            "obj_types_found": list(set(obj_types)) if obj_types else [],
            "n_views": n_views,
            "n_dimensions": n_dims,
            "has_draw_page": has_draw_page,
        }
    }
