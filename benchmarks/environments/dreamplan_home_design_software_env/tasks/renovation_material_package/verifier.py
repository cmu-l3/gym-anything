#!/usr/bin/env python3
"""
Verifier for renovation_material_package task.

The agent (interior designer) must:
1. Apply hardwood flooring to living room, kitchen tile, bedroom hardwood
2. Update wall color/material in at least one room
3. Export 3D view  → C:\\Users\\Docker\\Desktop\\renovation_3d_view.jpg
4. Export 2D floor plan → C:\\Users\\Docker\\Desktop\\renovation_floor_plan.jpg
5. Save project → C:\\Users\\Docker\\Documents\\renovation_proposal.dpn

Scoring (100 points total):
  - renovation_3d_view.jpg exists AND is new (after task start): 20 pts
  - renovation_3d_view.jpg size > 30 KB (real rendered image): 20 pts
  - renovation_floor_plan.jpg exists AND is new: 15 pts
  - renovation_floor_plan.jpg size > 10 KB (real floor plan): 10 pts
  - renovation_proposal.dpn exists AND is new: 25 pts
  - renovation_proposal.dpn size > 0: 10 pts

Pass threshold: >= 60 points AND at least one image file exists and is new.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\renovation_material_package_result.json"


def verify_renovation_material_package(traj, env_info, task_info):
    """
    Verify renovation material package task.

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

    # Helper to safely read file info dict
    def fi(key):
        v = result.get(key, {})
        if not isinstance(v, dict):
            return {}
        return v

    r3d      = fi('renovation_3d_view_jpg')
    rblue    = fi('renovation_floor_plan_jpg')
    rproject = fi('renovation_proposal_dpn')

    # Criterion 1: 3D view exists and is new (20 pts)
    if r3d.get('exists') and r3d.get('is_new'):
        score += 20
        feedback_parts.append("3D view exported (new file).")
    elif r3d.get('exists') and not r3d.get('is_new'):
        feedback_parts.append("3D view file found but predates task start (stale).")
    else:
        feedback_parts.append("MISSING: renovation_3d_view.jpg not found on Desktop.")

    # Criterion 2: 3D view has substantial content (20 pts)
    if r3d.get('exists') and r3d.get('is_new') and r3d.get('size_bytes', 0) >= 30000:
        score += 20
        feedback_parts.append(f"3D view has real content ({r3d['size_bytes']:,} bytes >= 30 KB).")
    elif r3d.get('exists') and r3d.get('is_new'):
        feedback_parts.append(f"3D view too small ({r3d.get('size_bytes', 0):,} bytes), may be empty/thumbnail.")

    # Criterion 3: Floor plan exists and is new (15 pts)
    if rblue.get('exists') and rblue.get('is_new'):
        score += 15
        feedback_parts.append("Floor plan exported (new file).")
    elif rblue.get('exists') and not rblue.get('is_new'):
        feedback_parts.append("Floor plan file found but predates task start (stale).")
    else:
        feedback_parts.append("MISSING: renovation_floor_plan.jpg not found on Desktop.")

    # Criterion 4: Floor plan has content (10 pts)
    if rblue.get('exists') and rblue.get('is_new') and rblue.get('size_bytes', 0) >= 10000:
        score += 10
        feedback_parts.append(f"Floor plan has content ({rblue['size_bytes']:,} bytes >= 10 KB).")
    elif rblue.get('exists') and rblue.get('is_new'):
        feedback_parts.append(f"Floor plan too small ({rblue.get('size_bytes', 0):,} bytes).")

    # Criterion 5: Project file saved and is new (25 pts)
    if rproject.get('exists') and rproject.get('is_new'):
        score += 25
        feedback_parts.append("Project saved to renovation_proposal.dpn (new file).")
    elif rproject.get('exists') and not rproject.get('is_new'):
        feedback_parts.append("Project file found but predates task start (stale).")
    else:
        feedback_parts.append("MISSING: renovation_proposal.dpn not saved to Documents.")

    # Criterion 6: Project file is non-empty (10 pts)
    if rproject.get('exists') and rproject.get('is_new') and rproject.get('size_bytes', 0) > 0:
        score += 10
        feedback_parts.append(f"Project file is non-empty ({rproject['size_bytes']:,} bytes).")

    score = min(score, 100)

    # Pass requires >= 60 points AND at least one image file is new
    any_image_new = (r3d.get('exists') and r3d.get('is_new')) or \
                    (rblue.get('exists') and rblue.get('is_new'))
    passed = score >= 60 and any_image_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
