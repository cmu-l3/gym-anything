#!/usr/bin/env python3
"""
Verifier for Hurricane Katrina Track Analysis task.

Scoring (100 points total):
  - File created during task:           10 pts
  - Data points imported correctly:     30 pts (Based on coordinates matching CSV)
  - Polyline path constructed:          20 pts
  - Distance calculation correct:       30 pts (Value between 2000-3000 km found)
  - Annotation (units) present:         10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_hurricane_katrina_track_analysis(traj, env_info, task_info):
    """Verify the Katrina track analysis task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from VM
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
    
    # 1. File Check (10 pts)
    if result.get('file_found', False) and result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created (+10)")
    elif result.get('file_found', False):
        feedback_parts.append("File found but not created in this session (0/10)")
    else:
        feedback_parts.append("File not found (0/10)")

    # 2. Data Points (30 pts)
    # We expect 8 points. Give partial credit.
    correct_points = result.get('correct_points', 0)
    # Max points 8. 
    # If >= 6 points match: 30 pts
    # If >= 4 points match: 15 pts
    if correct_points >= 6:
        score += 30
        feedback_parts.append(f"Data points verified ({correct_points}/8) (+30)")
    elif correct_points >= 4:
        score += 15
        feedback_parts.append(f"Some data points verified ({correct_points}/8) (+15)")
    else:
        feedback_parts.append(f"Few or no correct data points found ({correct_points}/8). Ensure Longitude=x, Latitude=y. (0/30)")

    # 3. Polyline (20 pts)
    if result.get('polyline_found', False):
        score += 20
        feedback_parts.append("Path (Polyline) constructed (+20)")
    else:
        feedback_parts.append("Path not found (Polyline expected) (0/20)")

    # 4. Distance Calculation (30 pts)
    # Looking for a value between 2000 and 3000
    if result.get('distance_value_found', False):
        score += 30
        val = result.get('extracted_distance')
        feedback_parts.append(f"Distance calculation found ({val} km) (+30)")
    else:
        feedback_parts.append("Total distance in km not found (expected ~2500) (0/30)")

    # 5. Annotation (10 pts)
    if result.get('annotation_found', False):
        score += 10
        feedback_parts.append("Unit annotation found (+10)")
    else:
        feedback_parts.append("Unit text (km) not found (0/10)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }