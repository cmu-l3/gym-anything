#!/usr/bin/env python3
"""
Verifier for structural_gusset_plate task.

Scoring (100 points total, pass >= 70):
  - FCStd file (gusset_plate.FCStd) exists:                10 pts
  - FCStd modified after task start:                       10 pts
  - Has Spreadsheet::Sheet (BOM table):                    15 pts
  - Has PartDesign::Body + >= 1 Pad (main plate):          10 pts
  - Has >= 6 bolt hole features (two bolt groups):         30 pts
  - Has Chamfer or Fillet (weld prep):                     10 pts
  - STEP file exported (> 5000 bytes):                     15 pts
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# PartDesign features that can represent bolt holes
HOLE_TYPES = {'PartDesign::Hole', 'PartDesign::Pocket'}

# PartDesign edge treatment features (weld prep)
EDGE_FEATURES = {'PartDesign::Chamfer', 'PartDesign::Fillet'}

# Part workbench alternatives
PART_CUT_TYPES = {'Part::Cut', 'Part::MultiCut', 'Part::Boolean'}


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


def verify_structural_gusset_plate(traj, env_info, task_info):
    """Verify structural steel gusset plate connection design."""
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
        copy_from_env('/tmp/structural_gusset_plate_result.json', json_local)
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
            copy_from_env('/home/ga/Documents/FreeCAD/gusset_plate.FCStd', fcstd_local)
            obj_types, doc_root = _parse_fcstd(fcstd_local)
        except Exception as e:
            logger.warning(f"Could not copy/parse gusset_plate.FCStd: {e}")
        finally:
            if fcstd_local and os.path.exists(fcstd_local):
                try:
                    os.unlink(fcstd_local)
                except Exception:
                    pass

    # Criterion 1: FCStd exists
    if obj_types is not None:
        score += 10
        feedback_parts.append("gusset_plate.FCStd exists and is valid")
    else:
        feedback_parts.append("gusset_plate.FCStd missing or invalid")
        step_size = int(result_meta.get('step_size', 0))
        if step_size > 5000:
            score += 15
            feedback_parts.append(f"STEP file present ({step_size} bytes) — but no FCStd")
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

    # Criterion 3: Spreadsheet (BOM table)
    has_spreadsheet = any('Spreadsheet::Sheet' in t for t in obj_types)
    if has_spreadsheet:
        score += 15
        feedback_parts.append("Spreadsheet (BOM table) present")
    else:
        feedback_parts.append("No Spreadsheet found — no BOM table created")

    # Criterion 4: PartDesign Body + Pad
    has_body = any('PartDesign::Body' in t for t in obj_types)
    pad_count = sum(1 for t in obj_types if t == 'PartDesign::Pad')
    if has_body and pad_count >= 1:
        score += 10
        feedback_parts.append(f"PartDesign Body with {pad_count} Pad(s) (plate body)")
    elif has_body or pad_count >= 1:
        score += 4
        feedback_parts.append("Partial PartDesign structure (Body or Pad missing)")
    else:
        # Check Part workbench alternative
        has_part_box = any('Part::Box' in t for t in obj_types)
        if has_part_box:
            score += 5
            feedback_parts.append("Part::Box used (alternative to PartDesign Pad)")
        else:
            feedback_parts.append("No plate body feature found")

    # Criterion 5: Bolt holes (>= 6 required, 8 total per spec)
    n_pd_holes = sum(1 for t in obj_types if t in HOLE_TYPES)
    n_part_cuts = sum(1 for t in obj_types if t in PART_CUT_TYPES)
    n_total_holes = n_pd_holes + n_part_cuts  # Accept both approaches

    if n_total_holes >= 8:
        score += 30
        feedback_parts.append(f"Has {n_total_holes} bolt hole features (both bolt groups complete)")
    elif n_total_holes >= 6:
        score += 30
        feedback_parts.append(f"Has {n_total_holes} bolt hole features (meets minimum)")
    elif n_total_holes >= 4:
        score += 18
        feedback_parts.append(f"Has {n_total_holes} bolt hole features (partial — only one bolt group)")
    elif n_total_holes >= 2:
        score += 8
        feedback_parts.append(f"Has {n_total_holes} bolt hole features")
    elif n_total_holes >= 1:
        score += 3
        feedback_parts.append(f"Has {n_total_holes} bolt hole feature")
    else:
        feedback_parts.append("No bolt holes found")

    # Criterion 6: Chamfer or Fillet (weld prep)
    has_chamfer = any('PartDesign::Chamfer' in t for t in obj_types)
    has_fillet = any('PartDesign::Fillet' in t for t in obj_types)

    if has_chamfer:
        score += 10
        feedback_parts.append("Chamfer feature present (weld bevel prep)")
    elif has_fillet:
        score += 10
        feedback_parts.append("Fillet feature present (accepted as weld prep)")
    else:
        feedback_parts.append("No chamfer or fillet found (no weld preparation feature)")

    # Criterion 7: STEP file
    step_exists = result_meta.get('step_exists', False)
    step_size = int(result_meta.get('step_size', 0))

    if step_exists and step_size > 5000:
        score += 15
        feedback_parts.append(f"STEP file exported successfully ({step_size} bytes)")
    elif step_exists and step_size > 0:
        score += 5
        feedback_parts.append(f"STEP file present but very small ({step_size} bytes)")
    else:
        feedback_parts.append("No STEP file found at gusset_plate.step or gusset_plate.stp")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": {
            "obj_types_found": list(set(obj_types)) if obj_types else [],
            "n_bolt_holes": n_total_holes if obj_types else 0,
            "has_weld_prep": (has_chamfer or has_fillet) if obj_types else False,
            "has_spreadsheet": has_spreadsheet if obj_types else False,
        }
    }
