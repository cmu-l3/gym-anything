#!/usr/bin/env python3
"""
Verifier for Parametric Bottle Volume Design task.

Scoring (100 points total):
  - File created during task: 10 pts
  - Profile Function defined: 20 pts
  - Surface created (3D model): 20 pts
  - Integral command present: 20 pts
  - Volume Target Met (495-505 ml): 30 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70
TARGET_VOLUME = 500.0
TOLERANCE = 5.0

def verify_parametric_bottle_volume_design(traj, env_info, task_info):
    """Verify the bottle design task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except OSError:
                pass
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # 1. File Created (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        subscores['file_created'] = True
        feedback_parts.append("File created (+10)")
    else:
        subscores['file_created'] = False
        feedback_parts.append("File not found or old (0/10)")

    # 2. Profile Function (20 pts)
    if result.get('has_function'):
        score += 20
        subscores['has_function'] = True
        feedback_parts.append("Profile function found (+20)")
    else:
        subscores['has_function'] = False
        feedback_parts.append("No function definition found (0/20)")

    # 3. Surface Command (20 pts)
    if result.get('has_surface_command'):
        score += 20
        subscores['has_surface'] = True
        feedback_parts.append("3D Surface found (+20)")
    else:
        subscores['has_surface'] = False
        feedback_parts.append("Surface command not found (0/20)")

    # 4. Integral Command (20 pts)
    if result.get('has_integral_command'):
        score += 20
        subscores['has_integral'] = True
        feedback_parts.append("Integral calculation found (+20)")
    else:
        subscores['has_integral'] = False
        feedback_parts.append("Integral command not found (0/20)")

    # 5. Volume Accuracy (30 pts)
    # We check both the specifically identified volume from Integral command
    # AND the best candidate found in the file, giving benefit of the doubt.
    vol_calc = result.get('calculated_volume')
    vol_best = result.get('best_volume_candidate')
    
    volume_ok = False
    final_vol = None

    if vol_calc is not None and abs(vol_calc - TARGET_VOLUME) <= TOLERANCE:
        volume_ok = True
        final_vol = vol_calc
    elif vol_best is not None and abs(vol_best - TARGET_VOLUME) <= TOLERANCE:
        volume_ok = True
        final_vol = vol_best
    
    if volume_ok:
        score += 30
        subscores['volume_accuracy'] = True
        feedback_parts.append(f"Volume target met: {final_vol:.2f} ml (+30)")
    else:
        subscores['volume_accuracy'] = False
        display_vol = vol_calc if vol_calc is not None else (vol_best if vol_best is not None else "N/A")
        feedback_parts.append(f"Volume target missed. Found: {display_vol} (Target: {TARGET_VOLUME}±{TOLERANCE}) (0/30)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }