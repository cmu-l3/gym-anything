#!/usr/bin/env python3
"""
Verifier for eia_rack_panel_design task.

Scoring (100 points total, pass >= 70):
  - FCStd file (rack_panel.FCStd) exists:                10 pts
  - FCStd modified after task start:                     10 pts
  - Has Spreadsheet::Sheet with >= 3 named cells:        20 pts
  - Has PartDesign::Body + >= 1 Pad:                     10 pts
  - Has >= 4 pocket/hole features (cutouts + mounting):  25 pts
  - STEP file exported (> 5000 bytes):                   25 pts
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


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


def _count_spreadsheet_aliases(root):
    """Count cells with non-empty alias in all Spreadsheet objects."""
    count = 0
    for cell in root.findall('.//Cell'):
        if cell.get('alias', '').strip():
            count += 1
    return count


def verify_eia_rack_panel_design(traj, env_info, task_info):
    """Verify EIA-310 1U rack panel design task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []

    # ---- Step 1: Load result JSON ----
    result_meta = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
            json_local = tf.name
        copy_from_env('/tmp/eia_rack_panel_design_result.json', json_local)
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
        fcstd_local = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd') as tf:
                fcstd_local = tf.name
            copy_from_env('/home/ga/Documents/FreeCAD/rack_panel.FCStd', fcstd_local)
            obj_types, doc_root = _parse_fcstd(fcstd_local)
        except Exception as e:
            logger.warning(f"Could not copy/parse rack_panel.FCStd: {e}")
        finally:
            if fcstd_local and os.path.exists(fcstd_local):
                try:
                    os.unlink(fcstd_local)
                except Exception:
                    pass

    # Criterion 1: FCStd exists
    if obj_types is not None:
        score += 10
        feedback_parts.append("rack_panel.FCStd exists and is valid")
    else:
        feedback_parts.append("rack_panel.FCStd missing or invalid")
        step_exists = result_meta.get('step_exists', False)
        step_size = int(result_meta.get('step_size', 0))
        if step_exists and step_size > 5000:
            score += 25
            feedback_parts.append(f"STEP file exported ({step_size} bytes) — but no FCStd")
        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Modified after task start
    if task_start > 0 and fcstd_mtime > 0 and int(fcstd_mtime) > int(task_start):
        score += 10
        feedback_parts.append("FCStd modified after task start")
    elif task_start == 0 and fcstd_size > 2000:
        score += 5
        feedback_parts.append("FCStd timestamp unavailable (partial credit)")
    else:
        feedback_parts.append("FCStd not modified after task start")

    # Criterion 3: Spreadsheet with named params
    has_spreadsheet = any('Spreadsheet::Sheet' in t for t in obj_types)
    if has_spreadsheet and doc_root is not None:
        alias_count = _count_spreadsheet_aliases(doc_root)
        if alias_count >= 3:
            score += 20
            feedback_parts.append(f"Parametric Spreadsheet with {alias_count} named parameters")
        elif alias_count >= 1:
            score += 10
            feedback_parts.append(f"Spreadsheet present but only {alias_count} named param(s) (need >= 3)")
        else:
            score += 5
            feedback_parts.append("Spreadsheet present but no named parameters (no aliases)")
    elif has_spreadsheet:
        score += 8
        feedback_parts.append("Spreadsheet present (could not check aliases)")
    else:
        feedback_parts.append("No Spreadsheet — design is not parametric")

    # Criterion 4: PartDesign Body + Pad
    has_body = any('PartDesign::Body' in t for t in obj_types)
    pad_count = sum(1 for t in obj_types if t == 'PartDesign::Pad')
    if has_body and pad_count >= 1:
        score += 10
        feedback_parts.append(f"PartDesign Body with {pad_count} Pad(s) (main panel body)")
    elif has_body:
        score += 4
        feedback_parts.append("PartDesign Body present but no Pad feature")
    else:
        feedback_parts.append("No PartDesign Body found")

    # Criterion 5: Cutout/hole features
    hole_pocket_types = {'PartDesign::Hole', 'PartDesign::Pocket'}
    n_cutouts = sum(1 for t in obj_types if t in hole_pocket_types)
    if n_cutouts >= 5:
        score += 25
        feedback_parts.append(f"Has {n_cutouts} cutout/hole features (connectors + mounting holes)")
    elif n_cutouts >= 4:
        score += 25
        feedback_parts.append(f"Has {n_cutouts} cutout/hole features (meets minimum)")
    elif n_cutouts >= 3:
        score += 15
        feedback_parts.append(f"Has {n_cutouts} cutout/hole features (partial — need >= 4)")
    elif n_cutouts >= 2:
        score += 8
        feedback_parts.append(f"Has {n_cutouts} cutout/hole features")
    elif n_cutouts >= 1:
        score += 3
        feedback_parts.append(f"Has {n_cutouts} cutout/hole feature")
    else:
        feedback_parts.append("No connector cutouts or mounting holes found")

    # Criterion 6: STEP file
    step_exists = result_meta.get('step_exists', False)
    step_size = int(result_meta.get('step_size', 0))

    if step_exists and step_size > 5000:
        score += 25
        feedback_parts.append(f"STEP file exported successfully ({step_size} bytes)")
    elif step_exists and step_size > 0:
        score += 8
        feedback_parts.append(f"STEP file present but very small ({step_size} bytes)")
    else:
        feedback_parts.append("No STEP file found at rack_panel.step or rack_panel.stp")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": {
            "obj_types_found": list(set(obj_types)) if obj_types else [],
            "n_cutouts": n_cutouts if obj_types else 0,
            "has_spreadsheet": has_spreadsheet if obj_types else False,
        }
    }
