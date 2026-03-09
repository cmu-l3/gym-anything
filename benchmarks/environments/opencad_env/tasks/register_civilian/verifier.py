#!/usr/bin/env python3
"""Verifier for register_civilian task."""

import json
import tempfile
import os


def verify_register_civilian(traj, env_info, task_info):
    """Verify a civilian identity was registered in OpenCAD."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_first = metadata.get('expected_first_name', 'Wade').lower()
    expected_last = metadata.get('expected_last_name', 'Hebert').lower()
    expected_dob = metadata.get('expected_dob', '1991-04-17')
    expected_gender = metadata.get('expected_gender', 'Male').lower()
    expected_address = metadata.get('expected_address', '').lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/register_civilian_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Check 1: Civilian found in database (20 pts)
    if result.get('civilian_found'):
        score += 20
        feedback_parts.append("Civilian record found in database")
    else:
        feedback_parts.append("No civilian record found")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    civ = result.get('civilian', {})

    # Check 2: Name contains expected first and last name (30 pts)
    # OpenCAD stores name as a single field e.g. "Wade Hebert"
    name = (civ.get('name') or '').strip().lower()
    first_match = expected_first in name
    last_match = expected_last in name
    if first_match and last_match:
        score += 30
        feedback_parts.append(f"Name matches: {civ.get('name')}")
    elif first_match or last_match:
        score += 15
        feedback_parts.append(f"Name partial match: {civ.get('name')}")
    else:
        feedback_parts.append(f"Name mismatch: expected '{expected_first} {expected_last}', got '{name}'")

    # Check 3: Date of birth matches (15 pts)
    dob = (civ.get('dob') or '').strip()
    if expected_dob in dob:
        score += 15
        feedback_parts.append(f"DOB matches: {dob}")
    else:
        feedback_parts.append(f"DOB mismatch: expected '{expected_dob}', got '{dob}'")

    # Check 4: Gender matches (10 pts)
    gender = (civ.get('gender') or '').strip().lower()
    if gender == expected_gender:
        score += 10
        feedback_parts.append(f"Gender matches: {civ.get('gender')}")
    else:
        feedback_parts.append(f"Gender mismatch: expected '{expected_gender}', got '{gender}'")

    # Check 5: Address contains expected text (15 pts)
    address = (civ.get('address') or '').strip().lower()
    if expected_address and expected_address in address:
        score += 15
        feedback_parts.append(f"Address matches")
    elif 'forum' in address and 'davis' in address:
        score += 10
        feedback_parts.append(f"Address partial match: {civ.get('address')}")
    elif 'forum drive' in address or '1432' in address:
        score += 5
        feedback_parts.append(f"Address weak match: {civ.get('address')}")
    else:
        feedback_parts.append(f"Address mismatch: got '{address}'")

    # Check 6: New record was created (10 pts)
    initial = result.get('initial_civilian_count', 0)
    current = result.get('current_civilian_count', 0)
    if current > initial:
        score += 10
        feedback_parts.append("New civilian record confirmed")
    else:
        feedback_parts.append("No new civilian records detected")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
