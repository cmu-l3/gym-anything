#!/usr/bin/env python3
"""
Verifier for exterior_landscape_design task.

The agent (landscape architect) must:
1. Add at least 4 trees/shrubs around the property
2. Add a driveway or walkway/path
3. Add an outdoor living structure (deck, patio, terrace, pergola)
4. Update exterior wall material or color
5. Export overhead site plan → C:\\Users\\Docker\\Desktop\\landscape_site_plan.jpg
6. Export 3D exterior view → C:\\Users\\Docker\\Desktop\\landscape_3d_view.jpg
7. Save project → C:\\Users\\Docker\\Documents\\landscape_design.dpn

Scoring (100 points total):
  - landscape_site_plan.jpg exists AND is new: 25 pts
  - landscape_site_plan.jpg size > 15 KB: 15 pts
  - landscape_3d_view.jpg exists AND is new: 25 pts
  - landscape_3d_view.jpg size > 30 KB: 15 pts
  - landscape_design.dpn exists AND is new: 15 pts
  - landscape_design.dpn non-empty: 5 pts

Pass threshold: >= 60 points AND both image files exist and are new.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\exterior_landscape_design_result.json"


def verify_exterior_landscape_design(traj, env_info, task_info):
    """
    Verify exterior landscape design task.

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

    rsiteplan = fi('landscape_site_plan_jpg')
    r3d       = fi('landscape_3d_view_jpg')
    rproject  = fi('landscape_design_dpn')

    # Criterion 1: Site plan exists and is new (25 pts)
    if rsiteplan.get('exists') and rsiteplan.get('is_new'):
        score += 25
        feedback_parts.append("Site plan (overhead view) exported.")
    elif rsiteplan.get('exists') and not rsiteplan.get('is_new'):
        feedback_parts.append("Site plan predates task start (stale).")
    else:
        feedback_parts.append("MISSING: landscape_site_plan.jpg not found on Desktop.")

    # Criterion 2: Site plan has real content (15 pts)
    if rsiteplan.get('exists') and rsiteplan.get('is_new') and rsiteplan.get('size_bytes', 0) >= 15000:
        score += 15
        feedback_parts.append(f"Site plan has content ({rsiteplan['size_bytes']:,} bytes >= 15 KB).")
    elif rsiteplan.get('exists') and rsiteplan.get('is_new'):
        feedback_parts.append(f"Site plan too small ({rsiteplan.get('size_bytes', 0):,} bytes).")

    # Criterion 3: 3D exterior view exists and is new (25 pts)
    if r3d.get('exists') and r3d.get('is_new'):
        score += 25
        feedback_parts.append("3D exterior perspective exported.")
    elif r3d.get('exists') and not r3d.get('is_new'):
        feedback_parts.append("3D exterior predates task start (stale).")
    else:
        feedback_parts.append("MISSING: landscape_3d_view.jpg not found on Desktop.")

    # Criterion 4: 3D exterior has real content (15 pts)
    if r3d.get('exists') and r3d.get('is_new') and r3d.get('size_bytes', 0) >= 30000:
        score += 15
        feedback_parts.append(f"3D exterior has content ({r3d['size_bytes']:,} bytes >= 30 KB).")
    elif r3d.get('exists') and r3d.get('is_new'):
        feedback_parts.append(f"3D exterior too small ({r3d.get('size_bytes', 0):,} bytes).")

    # Criterion 5: Project saved and is new (15 pts)
    if rproject.get('exists') and rproject.get('is_new'):
        score += 15
        feedback_parts.append("Project saved to landscape_design.dpn.")
    elif rproject.get('exists') and not rproject.get('is_new'):
        feedback_parts.append("Project file predates task start (stale).")
    else:
        feedback_parts.append("MISSING: landscape_design.dpn not saved to Documents.")

    # Criterion 6: Project file non-empty (5 pts)
    if rproject.get('exists') and rproject.get('is_new') and rproject.get('size_bytes', 0) > 0:
        score += 5
        feedback_parts.append(f"Project file non-empty ({rproject['size_bytes']:,} bytes).")

    score = min(score, 100)

    # Pass: >= 60 points AND both image files exist and are new
    both_images_new = (rsiteplan.get('exists') and rsiteplan.get('is_new')) and \
                      (r3d.get('exists') and r3d.get('is_new'))
    passed = score >= 60 and both_images_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
