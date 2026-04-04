#!/usr/bin/env python3
"""Verifier for create_bolo_vehicle task."""

import json
import tempfile
import os


def verify_create_bolo_vehicle(traj, env_info, task_info):
    """Verify a vehicle BOLO was created in OpenCAD."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_make = metadata.get('expected_make', 'Declasse').lower()
    expected_model = metadata.get('expected_model', 'Vigero').lower()
    expected_plate = metadata.get('expected_plate', 'XKCD420').upper()
    expected_color = metadata.get('expected_color', 'Black').lower()
    expected_keywords = metadata.get('expected_reason_keywords', [])
    expected_last_seen = metadata.get('expected_last_seen', 'Vinewood Boulevard').lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_bolo_vehicle_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Check 1: BOLO found (15 pts)
    if result.get('bolo_found'):
        score += 15
        feedback_parts.append("BOLO record found in database")
    else:
        feedback_parts.append("No BOLO record found")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    bolo = result.get('bolo', {})

    # Check 2: Vehicle make matches (15 pts)
    make = (bolo.get('make') or '').strip().lower()
    if expected_make in make or make in expected_make:
        score += 15
        feedback_parts.append(f"Make matches: {bolo.get('make')}")
    else:
        feedback_parts.append(f"Make mismatch: expected '{expected_make}', got '{make}'")

    # Check 3: Vehicle model matches (15 pts)
    model = (bolo.get('model') or '').strip().lower()
    if expected_model in model or model in expected_model:
        score += 15
        feedback_parts.append(f"Model matches: {bolo.get('model')}")
    else:
        feedback_parts.append(f"Model mismatch: expected '{expected_model}', got '{model}'")

    # Check 4: Plate matches (15 pts)
    plate = (bolo.get('plate') or '').strip().upper()
    if plate == expected_plate:
        score += 15
        feedback_parts.append(f"Plate matches: {plate}")
    elif expected_plate in plate:
        score += 10
        feedback_parts.append(f"Plate partial match: {plate}")
    else:
        feedback_parts.append(f"Plate mismatch: expected '{expected_plate}', got '{plate}'")

    # Check 5: Color matches (10 pts)
    color1 = (bolo.get('primary_color') or '').strip().lower()
    if expected_color in color1:
        score += 10
        feedback_parts.append(f"Color matches: {bolo.get('primary_color')}")
    else:
        feedback_parts.append(f"Color mismatch: expected '{expected_color}', got '{color1}'")

    # Check 6: Reason contains keywords (20 pts)
    reason = (bolo.get('reason') or '').lower()
    matched_kw = [kw for kw in expected_keywords if kw.lower() in reason]
    if len(expected_keywords) > 0:
        kw_ratio = len(matched_kw) / len(expected_keywords)
        kw_score = int(20 * kw_ratio)
        score += kw_score
        feedback_parts.append(f"Reason keywords: {len(matched_kw)}/{len(expected_keywords)} matched")
    else:
        score += 20

    # Check 7: New BOLO was created (10 pts)
    initial = result.get('initial_bolo_count', 0)
    current = result.get('current_bolo_count', 0)
    if current > initial:
        score += 10
        feedback_parts.append("New BOLO record confirmed")
    else:
        feedback_parts.append("No new BOLO records detected")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
