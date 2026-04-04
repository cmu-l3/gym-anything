#!/usr/bin/env python3
"""
Verifier for heatsink_fin_array_design task.

Scoring (100 points total, pass >= 70):
  - FCStd file (heatsink.FCStd) exists:                    10 pts
  - FCStd modified after task start:                       10 pts
  - Has Spreadsheet::Sheet with >= 4 named parameters:     20 pts
  - Has PartDesign::Body + >= 1 Pad (base plate):          10 pts
  - Has PartDesign::LinearPattern (fin array):             25 pts
  - Has >= 2 mounting hole/pocket features:                10 pts
  - STL file exported (> 1000 bytes):                       7 pts
  - STEP file exported (> 1000 bytes):                      8 pts
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
    """Count non-empty alias cells in all Spreadsheet objects."""
    count = 0
    for cell in root.findall('.//Cell'):
        if cell.get('alias', '').strip():
            count += 1
    return count


def verify_heatsink_fin_array_design(traj, env_info, task_info):
    """Verify parametric heatsink design with fin array."""
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
        copy_from_env('/tmp/heatsink_fin_array_design_result.json', json_local)
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
            copy_from_env('/home/ga/Documents/FreeCAD/heatsink.FCStd', fcstd_local)
            obj_types, doc_root = _parse_fcstd(fcstd_local)
        except Exception as e:
            logger.warning(f"Could not copy/parse heatsink.FCStd: {e}")
        finally:
            if fcstd_local and os.path.exists(fcstd_local):
                try:
                    os.unlink(fcstd_local)
                except Exception:
                    pass

    # Criterion 1: FCStd exists
    if obj_types is not None:
        score += 10
        feedback_parts.append("heatsink.FCStd exists and is valid")
    else:
        feedback_parts.append("heatsink.FCStd missing or invalid")
        # Partial check on export files
        stl_size = int(result_meta.get('stl_size', 0))
        step_size = int(result_meta.get('step_size', 0))
        if stl_size > 1000:
            score += 7
        if step_size > 1000:
            score += 8
        if score > 0:
            feedback_parts.append("Export files found without FCStd")
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
        feedback_parts.append("FCStd does not appear to be from this session")

    # Criterion 3: Spreadsheet with >= 4 named params
    has_spreadsheet = any('Spreadsheet::Sheet' in t for t in obj_types)
    alias_count = 0
    if has_spreadsheet and doc_root is not None:
        alias_count = _count_spreadsheet_aliases(doc_root)
        if alias_count >= 4:
            score += 20
            feedback_parts.append(f"Parametric Spreadsheet with {alias_count} named parameters (excellent)")
        elif alias_count >= 2:
            score += 12
            feedback_parts.append(f"Spreadsheet with {alias_count} named parameters (need >= 4 for full credit)")
        elif alias_count >= 1:
            score += 6
            feedback_parts.append(f"Spreadsheet with {alias_count} named parameter(s)")
        else:
            score += 4
            feedback_parts.append("Spreadsheet present but no named parameters")
    elif has_spreadsheet:
        score += 6
        feedback_parts.append("Spreadsheet present (alias count unavailable)")
    else:
        feedback_parts.append("No Spreadsheet workbench used — design is not parametric")

    # Criterion 4: PartDesign Body + Pad (base plate)
    has_body = any('PartDesign::Body' in t for t in obj_types)
    pad_count = sum(1 for t in obj_types if t == 'PartDesign::Pad')
    if has_body and pad_count >= 1:
        score += 10
        feedback_parts.append(f"PartDesign Body with {pad_count} Pad(s)")
    elif has_body or pad_count >= 1:
        score += 4
        feedback_parts.append("Partial PartDesign structure")
    else:
        feedback_parts.append("No PartDesign Body or Pad found")

    # Criterion 5: LinearPattern for fin array (KEY CRITERION)
    has_linear_pattern = any('PartDesign::LinearPattern' in t for t in obj_types)
    has_array = any('Part::Array' in t for t in obj_types)  # Alternative Part workbench approach

    if has_linear_pattern:
        score += 25
        feedback_parts.append("PartDesign LinearPattern found (fin array created correctly)")
    elif has_array:
        score += 12
        feedback_parts.append("Part::Array found (fin array via Part workbench — not PartDesign LinearPattern)")
    elif pad_count >= 5:
        # Agent might have created fins manually without using patterns
        score += 8
        feedback_parts.append(f"Found {pad_count} Pads (possible manual fin creation without LinearPattern)")
    else:
        feedback_parts.append("No LinearPattern found — fin array not created with PartDesign pattern feature")

    # Criterion 6: Mounting holes
    hole_pocket_types = {'PartDesign::Hole', 'PartDesign::Pocket'}
    n_mount_holes = sum(1 for t in obj_types if t in hole_pocket_types)

    if n_mount_holes >= 2:
        score += 10
        feedback_parts.append(f"Has {n_mount_holes} hole/pocket features (mounting holes present)")
    elif n_mount_holes >= 1:
        score += 4
        feedback_parts.append(f"Has {n_mount_holes} hole/pocket feature (need >= 2 mounting holes)")
    else:
        feedback_parts.append("No mounting holes found")

    # Criterion 7: STL export
    stl_exists = result_meta.get('stl_exists', False)
    stl_size = int(result_meta.get('stl_size', 0))
    if stl_exists and stl_size > 1000:
        score += 7
        feedback_parts.append(f"STL exported ({stl_size} bytes)")
    else:
        feedback_parts.append("No STL file at /home/ga/Documents/FreeCAD/heatsink.stl")

    # Criterion 8: STEP export
    step_exists = result_meta.get('step_exists', False)
    step_size = int(result_meta.get('step_size', 0))
    if step_exists and step_size > 1000:
        score += 8
        feedback_parts.append(f"STEP exported ({step_size} bytes)")
    else:
        feedback_parts.append("No STEP file at /home/ga/Documents/FreeCAD/heatsink.step")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": {
            "obj_types_found": list(set(obj_types)) if obj_types else [],
            "has_linear_pattern": has_linear_pattern if obj_types else False,
            "n_mount_holes": n_mount_holes if obj_types else 0,
            "spreadsheet_aliases": alias_count,
        }
    }
