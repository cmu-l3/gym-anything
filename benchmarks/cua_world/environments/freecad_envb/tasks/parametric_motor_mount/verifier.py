#!/usr/bin/env python3
"""
Verifier for parametric_motor_mount task.

Scoring (100 points total, pass >= 70):
  - FCStd file exists and is valid ZIP:            10 pts
  - FCStd modified after task start:               10 pts
  - Has Spreadsheet::Sheet object:                 15 pts
  - Spreadsheet has >= 3 named cells (aliases):    10 pts  (subset of Spreadsheet pts)
  - Has PartDesign::Body:                           5 pts
  - Has >= 1 PartDesign::Pad:                       5 pts
  - Has >= 4 hole/pocket features (motor bolts):   20 pts
  - Has >= 6 hole/pocket features (+ frame holes): 10 pts
  - STL file exists (> 5000 bytes):                25 pts
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def _parse_fcstd(fcstd_path):
    """Parse FCStd ZIP and return list of object type strings from Document.xml.
    Returns (obj_types, root_element) or (None, None) on error."""
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
    """Count cells with non-empty alias attribute in any Spreadsheet object."""
    count = 0
    for cell in root.findall('.//Cell'):
        alias = cell.get('alias', '').strip()
        if alias:
            count += 1
    return count


def verify_parametric_motor_mount(traj, env_info, task_info):
    """Verify parametric NEMA 17 motor mount design task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []

    # ---- Step 1: Copy result JSON (timestamps) ----
    result_meta = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
            json_local = tf.name
        copy_from_env('/tmp/parametric_motor_mount_result.json', json_local)
        with open(json_local, 'r') as f:
            result_meta = json.load(f)
        os.unlink(json_local)
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
        # Proceed without timestamps — will fail timestamp check

    task_start = int(result_meta.get('task_start', 0))

    # ---- Step 2: Copy and validate FCStd ----
    fcstd_local = None
    obj_types = None
    doc_root = None

    fcstd_exists_meta = result_meta.get('fcstd_exists', False)
    fcstd_mtime = int(result_meta.get('fcstd_mtime', 0))
    fcstd_size = int(result_meta.get('fcstd_size', 0))

    if fcstd_exists_meta:
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd') as tf:
                fcstd_local = tf.name
            copy_from_env('/home/ga/Documents/FreeCAD/motor_mount.FCStd', fcstd_local)
            obj_types, doc_root = _parse_fcstd(fcstd_local)
        except Exception as e:
            logger.warning(f"Could not copy/parse FCStd: {e}")
        finally:
            if fcstd_local and os.path.exists(fcstd_local):
                try:
                    os.unlink(fcstd_local)
                except Exception:
                    pass

    # Criterion 1: FCStd exists and is parseable
    if obj_types is not None:
        score += 10
        feedback_parts.append("FCStd file exists and is valid")
    else:
        feedback_parts.append("FCStd file missing or invalid")
        # Without FCStd, check only STL
        stl_exists = result_meta.get('stl_exists', False)
        stl_size = int(result_meta.get('stl_size', 0))
        if stl_exists and stl_size > 5000:
            score += 25
            feedback_parts.append(f"STL exported ({stl_size} bytes)")
        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: FCStd modified after task start
    if task_start > 0 and fcstd_mtime > 0 and int(fcstd_mtime) > int(task_start):
        score += 10
        feedback_parts.append("FCStd modified after task start")
    elif task_start == 0:
        # Can't check timestamp, award partial credit if file looks substantial
        if fcstd_size > 2000:
            score += 5
            feedback_parts.append("FCStd timestamp not available (partial credit)")
    else:
        feedback_parts.append("FCStd not modified after task start (may be pre-existing)")

    # Criterion 3: Has Spreadsheet::Sheet
    has_spreadsheet = any('Spreadsheet::Sheet' in t for t in obj_types)
    if has_spreadsheet:
        score += 15
        feedback_parts.append("Spreadsheet workbench used")
        # Criterion 3a: Spreadsheet has >= 3 named cells
        if doc_root is not None:
            alias_count = _count_spreadsheet_aliases(doc_root)
            if alias_count >= 3:
                score += 10
                feedback_parts.append(f"Spreadsheet has {alias_count} named parameters")
            elif alias_count >= 1:
                score += 4
                feedback_parts.append(f"Spreadsheet has only {alias_count} named parameter(s) (need >= 3)")
            else:
                feedback_parts.append("Spreadsheet has no named parameters (aliases)")
    else:
        feedback_parts.append("No Spreadsheet workbench used — design is not parametric")

    # Criterion 4: Has PartDesign::Body
    has_body = any('PartDesign::Body' in t for t in obj_types)
    if has_body:
        score += 5
        feedback_parts.append("PartDesign Body present")
    else:
        feedback_parts.append("No PartDesign Body found")

    # Criterion 5: Has >= 1 PartDesign::Pad
    pad_count = sum(1 for t in obj_types if t == 'PartDesign::Pad')
    if pad_count >= 1:
        score += 5
        feedback_parts.append(f"Has {pad_count} Pad feature(s)")
    else:
        feedback_parts.append("No Pad feature found (no base body extruded)")

    # Criterion 6 & 7: Count hole/pocket features
    hole_types = {'PartDesign::Hole', 'PartDesign::Pocket'}
    n_holes = sum(1 for t in obj_types if t in hole_types)

    if n_holes >= 4:
        score += 20
        feedback_parts.append(f"Has {n_holes} hole/pocket features (motor bolt holes present)")
        if n_holes >= 6:
            score += 10
            feedback_parts.append(f"Has {n_holes} features including frame mounting holes")
    elif n_holes >= 2:
        score += 8
        feedback_parts.append(f"Has {n_holes} hole/pocket features (partial — need >= 4 for motor bolts)")
    elif n_holes >= 1:
        score += 3
        feedback_parts.append(f"Has only {n_holes} hole/pocket feature")
    else:
        feedback_parts.append("No hole or pocket features found")

    # Criterion 8: STL exported
    stl_exists = result_meta.get('stl_exists', False)
    stl_size = int(result_meta.get('stl_size', 0))
    stl_mtime = int(result_meta.get('stl_mtime', 0))

    if stl_exists and stl_size > 5000:
        score += 25
        feedback_parts.append(f"STL exported successfully ({stl_size} bytes)")
    elif stl_exists and stl_size > 0:
        score += 8
        feedback_parts.append(f"STL exported but very small ({stl_size} bytes — possibly empty mesh)")
    else:
        feedback_parts.append("No STL export found at /home/ga/Documents/FreeCAD/motor_mount.stl")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": {
            "obj_types_found": list(set(obj_types)) if obj_types else [],
            "n_hole_pocket": n_holes if obj_types else 0,
            "has_spreadsheet": has_spreadsheet if obj_types else False,
        }
    }
