#!/usr/bin/env python3
"""
Verifier for construction_document_set task.

The agent (general contractor) must:
1. Export front elevation view → C:\\Users\\Docker\\Desktop\\elevation_front.jpg
2. Export side elevation view → C:\\Users\\Docker\\Desktop\\elevation_side.jpg
3. Export 2D ground floor plan → C:\\Users\\Docker\\Desktop\\construction_floor_plan.jpg
4. Export 3D overview → C:\\Users\\Docker\\Desktop\\construction_overview.jpg
5. Save project → C:\\Users\\Docker\\Documents\\construction_docs.dpn

Scoring (100 points total):
  - elevation_front.jpg exists AND is new: 10 pts
  - elevation_front.jpg size > 10 KB: 5 pts
  - elevation_side.jpg exists AND is new: 10 pts
  - elevation_side.jpg size > 10 KB: 5 pts
  - construction_floor_plan.jpg exists AND is new: 10 pts
  - construction_floor_plan.jpg size > 10 KB: 5 pts
  - construction_overview.jpg exists AND is new: 10 pts
  - construction_overview.jpg size > 10 KB: 5 pts
  - construction_docs.dpn exists AND is new: 15 pts
  - construction_docs.dpn non-empty: 5 pts
  - All 4 image files present and new: 20 pts bonus

Pass threshold: >= 60 points AND at least 3 of 4 image files exist and are new.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\construction_document_set_result.json"


def verify_construction_document_set(traj, env_info, task_info):
    """
    Verify construction document set task.

    Reads result JSON from export_result.ps1 which contains per-file info:
      exists, size_bytes, mtime_unix, is_new
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    # ----------------------------------------------------------------
    # Load result JSON from VM
    # ----------------------------------------------------------------
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {result}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file. Export may have failed: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    # ----------------------------------------------------------------
    # Scoring
    # ----------------------------------------------------------------
    score = 0
    feedback_parts = []

    def fi(key):
        v = result.get(key, {})
        if not isinstance(v, dict):
            return {}
        return v

    refront    = fi('elevation_front_jpg')
    reside     = fi('elevation_side_jpg')
    refloor    = fi('construction_floor_plan_jpg')
    reoverview = fi('construction_overview_jpg')
    rproject   = fi('construction_docs_dpn')

    images = [
        ('elevation_front.jpg',         refront,    "Front elevation"),
        ('elevation_side.jpg',          reside,     "Side elevation"),
        ('construction_floor_plan.jpg', refloor,    "Floor plan"),
        ('construction_overview.jpg',   reoverview, "3D overview"),
    ]

    new_image_count = 0

    for fname, fdata, label in images:
        # Exists and is new (10 pts each)
        if fdata.get('exists') and fdata.get('is_new'):
            score += 10
            new_image_count += 1
            feedback_parts.append(f"{label} exported.")
        elif fdata.get('exists') and not fdata.get('is_new'):
            feedback_parts.append(f"{label} predates task start (stale).")
        else:
            feedback_parts.append(f"MISSING: {fname} not found on Desktop.")

        # Has real content (5 pts each)
        if fdata.get('exists') and fdata.get('is_new') and fdata.get('size_bytes', 0) >= 10000:
            score += 5
            feedback_parts.append(f"{label} has content ({fdata['size_bytes']:,} bytes).")
        elif fdata.get('exists') and fdata.get('is_new'):
            feedback_parts.append(f"{label} too small ({fdata.get('size_bytes', 0):,} bytes).")

    # Project file (15 + 5 pts)
    if rproject.get('exists') and rproject.get('is_new'):
        score += 15
        feedback_parts.append("Project saved to construction_docs.dpn.")
    elif rproject.get('exists') and not rproject.get('is_new'):
        feedback_parts.append("Project file predates task start (stale).")
    else:
        feedback_parts.append("MISSING: construction_docs.dpn not saved to Documents.")

    if rproject.get('exists') and rproject.get('is_new') and rproject.get('size_bytes', 0) > 0:
        score += 5
        feedback_parts.append(f"Project file non-empty ({rproject['size_bytes']:,} bytes).")

    # Bonus: all 4 image types present and new (20 pts)
    if new_image_count == 4:
        score += 20
        feedback_parts.append("Complete 4-view document set delivered!")
    else:
        feedback_parts.append(f"Only {new_image_count}/4 required view types delivered.")

    score = min(score, 100)

    # Pass: >= 60 points AND at least 3 of 4 image files are new
    passed = score >= 60 and new_image_count >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
