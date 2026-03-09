#!/usr/bin/env python3
"""
Verifier for second_floor_addition task.

The agent (residential architect) must:
1. Add a second floor to the Contemporary House
2. Create at least 2 rooms on the second floor
3. Add a staircase connecting ground and second floor
4. Add at least 1 window on the second floor
5. Export ground floor plan → C:\\Users\\Docker\\Desktop\\ground_floor_plan.jpg
6. Export second floor plan → C:\\Users\\Docker\\Desktop\\second_floor_plan.jpg
7. Export 3D exterior → C:\\Users\\Docker\\Desktop\\two_story_exterior.jpg
8. Save project → C:\\Users\\Docker\\Documents\\two_story_design.dpn

Scoring (100 points total):
  - ground_floor_plan.jpg exists AND is new: 20 pts
  - ground_floor_plan.jpg size > 10 KB: 10 pts
  - second_floor_plan.jpg exists AND is new: 20 pts
  - second_floor_plan.jpg size > 10 KB: 10 pts
  - two_story_exterior.jpg exists AND is new: 15 pts
  - two_story_exterior.jpg size > 30 KB: 10 pts
  - two_story_design.dpn exists AND is new: 10 pts
  - two_story_design.dpn non-empty: 5 pts

Pass threshold: >= 60 points AND both floor plans exist and are new.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\second_floor_addition_result.json"


def verify_second_floor_addition(traj, env_info, task_info):
    """
    Verify second floor addition task.

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

    rground   = fi('ground_floor_plan_jpg')
    rsecond   = fi('second_floor_plan_jpg')
    rexterior = fi('two_story_exterior_jpg')
    rproject  = fi('two_story_design_dpn')

    # Criterion 1: Ground floor plan exists and is new (20 pts)
    if rground.get('exists') and rground.get('is_new'):
        score += 20
        feedback_parts.append("Ground floor plan exported.")
    elif rground.get('exists') and not rground.get('is_new'):
        feedback_parts.append("Ground floor plan predates task start (stale).")
    else:
        feedback_parts.append("MISSING: ground_floor_plan.jpg not found on Desktop.")

    # Criterion 2: Ground floor plan has content (10 pts)
    if rground.get('exists') and rground.get('is_new') and rground.get('size_bytes', 0) >= 10000:
        score += 10
        feedback_parts.append(f"Ground floor plan has content ({rground['size_bytes']:,} bytes).")
    elif rground.get('exists') and rground.get('is_new'):
        feedback_parts.append(f"Ground floor plan too small ({rground.get('size_bytes', 0):,} bytes).")

    # Criterion 3: Second floor plan exists and is new (20 pts)
    if rsecond.get('exists') and rsecond.get('is_new'):
        score += 20
        feedback_parts.append("Second floor plan exported.")
    elif rsecond.get('exists') and not rsecond.get('is_new'):
        feedback_parts.append("Second floor plan predates task start (stale).")
    else:
        feedback_parts.append("MISSING: second_floor_plan.jpg not found on Desktop.")

    # Criterion 4: Second floor plan has content (10 pts)
    if rsecond.get('exists') and rsecond.get('is_new') and rsecond.get('size_bytes', 0) >= 10000:
        score += 10
        feedback_parts.append(f"Second floor plan has content ({rsecond['size_bytes']:,} bytes).")
    elif rsecond.get('exists') and rsecond.get('is_new'):
        feedback_parts.append(f"Second floor plan too small ({rsecond.get('size_bytes', 0):,} bytes).")

    # Criterion 5: 3D exterior exists and is new (15 pts)
    if rexterior.get('exists') and rexterior.get('is_new'):
        score += 15
        feedback_parts.append("3D exterior view exported.")
    elif rexterior.get('exists') and not rexterior.get('is_new'):
        feedback_parts.append("3D exterior predates task start (stale).")
    else:
        feedback_parts.append("MISSING: two_story_exterior.jpg not found on Desktop.")

    # Criterion 6: 3D exterior has real content (10 pts)
    if rexterior.get('exists') and rexterior.get('is_new') and rexterior.get('size_bytes', 0) >= 30000:
        score += 10
        feedback_parts.append(f"3D exterior has content ({rexterior['size_bytes']:,} bytes).")
    elif rexterior.get('exists') and rexterior.get('is_new'):
        feedback_parts.append(f"3D exterior too small ({rexterior.get('size_bytes', 0):,} bytes).")

    # Criterion 7: Project saved and is new (10 pts)
    if rproject.get('exists') and rproject.get('is_new'):
        score += 10
        feedback_parts.append("Project saved to two_story_design.dpn.")
    elif rproject.get('exists') and not rproject.get('is_new'):
        feedback_parts.append("Project file predates task start (stale).")
    else:
        feedback_parts.append("MISSING: two_story_design.dpn not saved to Documents.")

    # Criterion 8: Project file non-empty (5 pts)
    if rproject.get('exists') and rproject.get('is_new') and rproject.get('size_bytes', 0) > 0:
        score += 5
        feedback_parts.append(f"Project file non-empty ({rproject['size_bytes']:,} bytes).")

    score = min(score, 100)

    # Pass: >= 60 points AND both floor plans are new (proves second floor was actually created)
    both_plans_new = (rground.get('exists') and rground.get('is_new')) and \
                     (rsecond.get('exists') and rsecond.get('is_new'))
    passed = score >= 60 and both_plans_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
