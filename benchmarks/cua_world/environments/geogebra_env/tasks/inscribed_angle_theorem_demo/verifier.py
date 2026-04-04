#!/usr/bin/env python3
"""
Verifier for Inscribed Angle Theorem Demo task.

Scoring Criteria (100 pts total):
1. File created during task (15 pts)
2. Circle constructed (approx radius 3 at origin) (20 pts)
3. Points on circle (>= 3 points at distance ~3 from origin) (15 pts)
4. Angle measurements (>= 2 angles measured) (20 pts)
5. Angle Ratio Check (One angle approx 90, one approx 45) (15 pts)
6. Text annotation present (15 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_inscribed_angle_theorem_demo(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Get Metadata
    metadata = task_info.get('metadata', {})
    expected_central = metadata.get('expected_central_angle', 90.0)
    expected_inscribed = metadata.get('expected_inscribed_angle', 45.0)
    tol_angle = metadata.get('tolerance_angle', 5.0)

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # CRITERION 1: File Created (15 pts)
    file_found = result.get('file_found', False)
    created_during = result.get('file_created_during_task', False)
    
    if file_found and created_during:
        score += 15
        feedback_parts.append("File created during task (+15)")
    elif file_found:
        feedback_parts.append("File exists but not created during task (0/15)")
    else:
        feedback_parts.append("File not found (0/15)")
        # If no file, hard fail on rest usually, but let's check if they did anything
    
    # CRITERION 2: Circle Construction (20 pts)
    # Check explicitly for circle command or implicit via radius check
    has_circle = result.get('has_circle', False)
    if has_circle:
        score += 20
        feedback_parts.append("Circle construction detected (+20)")
    else:
        feedback_parts.append("Circle not detected (0/20)")
        
    # CRITERION 3: Points on Circle (15 pts)
    # We expect A, B, and C on the circle (radius 3)
    num_on_circle = result.get('num_points_on_circle', 0)
    if num_on_circle >= 3:
        score += 15
        feedback_parts.append(f"Found {num_on_circle} points on circle (+15)")
    elif num_on_circle >= 2:
        score += 10
        feedback_parts.append(f"Found {num_on_circle} points on circle (partial +10)")
    else:
        feedback_parts.append(f"Insufficient points on circle (found {num_on_circle}) (0/15)")

    # CRITERION 4: Angle Measurements (20 pts)
    # Expecting at least 2 angle measurements
    num_angles = result.get('num_angles', 0)
    if num_angles >= 2:
        score += 20
        feedback_parts.append(f"Found {num_angles} angle measurements (+20)")
    elif num_angles == 1:
        score += 10
        feedback_parts.append("Found only 1 angle measurement (+10)")
    else:
        feedback_parts.append("No angle measurements found (0/20)")

    # CRITERION 5: Angle Ratio / Values (15 pts)
    # Check if we have an angle near 90 and an angle near 45
    angle_vals = result.get('angle_values', [])
    # Normalize angles to [0, 360) just in case, though GeoGebra usually does [0, 360) or [0, 180)
    # We look for ~90 and ~45.
    
    has_90 = False
    has_45 = False
    
    for a in angle_vals:
        # Check 90
        if abs(a - expected_central) <= tol_angle:
            has_90 = True
        # Check 45 (or 315 if reflex, but task said acute)
        if abs(a - expected_inscribed) <= tol_angle:
            has_45 = True
            
    if has_90 and has_45:
        score += 15
        feedback_parts.append("Angle values match theorem (90° and 45°) (+15)")
    elif has_90 or has_45:
        score += 7
        feedback_parts.append("One correct angle value found (+7)")
    else:
        if angle_vals:
            feedback_parts.append(f"Angle values {angle_vals} do not match expected 90°/45° (0/15)")
        else:
            feedback_parts.append("No angle values to check (0/15)")

    # CRITERION 6: Text Annotation (15 pts)
    if result.get('has_text', False):
        score += 15
        feedback_parts.append("Text annotation found (+15)")
    else:
        feedback_parts.append("No text annotation found (0/15)")

    # Final result
    passed = score >= PASS_THRESHOLD and (num_angles >= 1) # Gate: must have at least one angle
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }