#!/usr/bin/env python3
"""
Verifier for Analemmatic Sundial Chicago task.

Criteria:
1. File exists and created during task.
2. Ellipse dimensions: 
   - Semi-major (x) approx 6.0
   - Semi-minor (y) approx 4.005 (6 * sin(41.88))
3. Key Points present:
   - Noon: (0, 4.005)
   - Solstices: (0, ±1.936) (6 * tan(23.44) * cos(41.88))
   - 3 PM: (4.242, 2.832) (6*sin(45), 4.005*cos(45))
4. Text annotations exist.
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

def verify_analemmatic_sundial_chicago(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_b = metadata.get('expected_semi_minor_b', 4.005)
    expected_solstice = metadata.get('expected_solstice_y', 1.936)
    tol_dist = metadata.get('tolerance_dist', 0.25)
    tol_axis = metadata.get('tolerance_axis', 0.2)

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created (+10)")
    else:
        feedback.append("File not found or not created during task (0/10)")

    points = result.get("points", [])
    
    # 2. Ellipse Check (30 pts)
    # Since extracting exact ellipse params from GGB XML is complex, we infer from the noon point (0, b)
    # and the 3pm point which must lie on the ellipse.
    # We look for a point close to (0, expected_b) which is Noon.
    noon_found = False
    noon_y = 0
    for p in points:
        # Check near (0, 4.005)
        if abs(p['x']) < tol_dist and abs(p['y'] - expected_b) < tol_dist:
            noon_found = True
            noon_y = p['y']
            break
            
    # Also check if a conic object exists
    has_conic = len(result.get("conics", [])) > 0
    
    if noon_found and has_conic:
        score += 30
        feedback.append(f"Ellipse/Noon point found at (0, {noon_y:.2f}) (+30)")
    elif noon_found:
        score += 20
        feedback.append("Noon point found, but ellipse object missing (+20)")
    elif has_conic:
        score += 10
        feedback.append("Ellipse object found, but Noon point missing (+10)")
    else:
        feedback.append("Missing Ellipse or Noon point (0/30)")

    # 3. Solstice Points (20 pts)
    # Expect (0, 1.936) and (0, -1.936)
    summer_found = False
    winter_found = False
    
    for p in points:
        if abs(p['x']) < tol_dist:
            if abs(p['y'] - expected_solstice) < tol_dist:
                summer_found = True
            if abs(p['y'] + expected_solstice) < tol_dist:
                winter_found = True
                
    if summer_found and winter_found:
        score += 20
        feedback.append("Both Solstice points found (+20)")
    elif summer_found or winter_found:
        score += 10
        feedback.append("One Solstice point found (+10)")
    else:
        feedback.append(f"Solstice points missing (expected y ≈ ±{expected_solstice}) (0/20)")

    # 4. Hour Markers (20 pts)
    # Check for 3 PM: (4.242, 2.832)
    # x = 6*sin(45), y = 4.005*cos(45)
    expected_3pm_x = 4.242
    expected_3pm_y = expected_b * 0.7071 # ~2.832
    
    p3pm_found = False
    for p in points:
        if abs(p['x'] - expected_3pm_x) < tol_dist and abs(p['y'] - expected_3pm_y) < tol_dist:
            p3pm_found = True
            break
            
    if p3pm_found:
        score += 20
        feedback.append("3 PM Hour marker found (+20)")
    else:
        feedback.append(f"3 PM marker missing (expected approx {expected_3pm_x:.1f}, {expected_3pm_y:.1f}) (0/20)")

    # 5. Annotations (20 pts)
    # Check if text elements exist or commands used to create text
    if len(result.get("texts", [])) > 0 or "Text" in result.get("commands", []):
        score += 20
        feedback.append("Annotations found (+20)")
    else:
        feedback.append("No annotations found (0/20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }