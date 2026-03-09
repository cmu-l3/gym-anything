#!/usr/bin/env python3
"""
Verifier for Belt Drive System Design task.

Scoring (100 points total):
  - File created during task: 10 pts
  - Driver/Driven Pulley Centers: 20 pts (Checks for points at (0,0) and (500,0))
  - Tangents/Belt Geometry: 20 pts (Checks for Tangent command or sufficient segments)
  - Wrap Angle: 20 pts (Checks for angle ~162.7 deg)
  - Belt Length: 30 pts (Checks for length ~1582 mm)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_belt_drive_system_design(traj, env_info, task_info):
    """Verify the belt drive system design task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_angle = metadata.get('expected_wrap_angle_deg', 162.75)
    expected_length = metadata.get('expected_belt_length_mm', 1582.4)
    tol_angle = metadata.get('tolerance_angle', 2.0)
    tol_length = metadata.get('tolerance_length', 10.0)

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

    # 1. File Check (10 pts)
    if result.get('file_found', False) and result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created (+10)")
    else:
        feedback_parts.append("File not found or old (0/10)")

    # 2. Geometry Check (Pulleys) (20 pts)
    # Check for center points (0,0) and (500,0)
    points = result.get('points_found', [])
    has_origin = any(math.hypot(p['x'], p['y']) < 1.0 for p in points)
    has_driven = any(math.hypot(p['x']-500, p['y']) < 1.0 for p in points)
    
    if has_origin and has_driven:
        score += 20
        feedback_parts.append("Pulley centers found (+20)")
    elif has_origin or has_driven:
        score += 10
        feedback_parts.append("One pulley center found (+10)")
    else:
        feedback_parts.append("Pulley centers (0,0) and (500,0) not found (0/20)")

    # 3. Tangents/Belt (20 pts)
    commands = result.get('commands_used', [])
    seg_count = result.get('segments_count', 0)
    # Either used Tangent command OR manually created enough segments (at least 2 for belt runs)
    if "Tangent" in commands or seg_count >= 2:
        score += 20
        feedback_parts.append("Belt tangents/segments found (+20)")
    else:
        feedback_parts.append("No tangents or belt segments found (0/20)")

    # 4. Wrap Angle (20 pts)
    # Look for a value close to 162.75
    numeric_vals = result.get('numeric_values', [])
    found_angle = False
    best_angle = 0
    
    # Check angles (often in range 0-360)
    # Sometimes GeoGebra reports reflex angle (360 - 162.75 = 197.25)
    # Or half angle logic
    for item in numeric_vals:
        val = item['value']
        # Check standard angle
        if abs(val - expected_angle) < tol_angle:
            found_angle = True
            best_angle = val
            break
        # Check reflex
        if abs(val - (360 - expected_angle)) < tol_angle:
            found_angle = True
            best_angle = val
            break
        # Check radians just in case (162 deg ~= 2.84 rad)
        if abs(val - math.radians(expected_angle)) < 0.1:
            found_angle = True
            best_angle = val * 180 / math.pi # convert for display
            break

    if found_angle:
        score += 20
        feedback_parts.append(f"Wrap angle {best_angle:.1f}° found (+20)")
    else:
        feedback_parts.append(f"Wrap angle ~{expected_angle}° not found (0/20)")

    # 5. Belt Length (30 pts)
    # Look for value close to 1582
    found_length = False
    best_length = 0
    for item in numeric_vals:
        val = item['value']
        if abs(val - expected_length) < tol_length:
            found_length = True
            best_length = val
            break
    
    if found_length:
        score += 30
        feedback_parts.append(f"Belt length {best_length:.1f} mm found (+30)")
    else:
        # Check if they summed components manually: 2 straight + 2 arcs
        # 2*494 + 142 + 430 approx
        # If we see measurement of ~1582 it counts.
        feedback_parts.append(f"Total belt length ~{expected_length} mm not found (0/30)")

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }