#!/usr/bin/env python3
"""Verifier for new_resident_full_processing task."""

import json
import tempfile
import os


def verify_new_resident_full_processing(traj, env_info, task_info):
    """Verify new civilian Lamar Davis, linked vehicle, and linked warrant.

    Scoring (100 pts, pass >= 70):
      Section 1 - Civilian Identity (25 pts, GATE + wrong-target):
        - No civilian found -> score=0 (gate)
        - Wrong name (not Lamar Davis) -> score=0 (wrong-target gate)
        - Name matches Lamar Davis: 15 pts
        - DOB matches 1988-09-05: 7 pts
        - Gender matches Male: 3 pts
      Section 2 - Vehicle Registration (35 pts):
        - Vehicle found: 10 pts
        - Plate contains LAM-8844: 15 pts
        - Vehicle linked to Lamar Davis identity: 10 pts
      Section 3 - Warrant (40 pts):
        - Warrant found: 15 pts
        - Warrant name contains 'stolen property' or 'receiving': 15 pts
        - Issuing agency contains 'blaine' or 'sheriff': 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_first = metadata.get('expected_first_name', 'Lamar').lower()
    expected_last = metadata.get('expected_last_name', 'Davis').lower()
    expected_dob = metadata.get('expected_dob', '1988-09-05')
    expected_plate = metadata.get('expected_plate', 'LAM-8844').upper().replace('-', '')
    expected_warrant = metadata.get('expected_warrant_name', 'Receiving Stolen Property').lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/new_resident_full_processing_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # === SECTION 1: CIVILIAN IDENTITY (25 pts) — GATE + WRONG-TARGET ===
    if not result.get('civilian_found'):
        feedback_parts.append("No new civilian record found in database")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    civ = result.get('civilian', {})
    name = (civ.get('name') or '').strip().lower()
    first_match = expected_first in name
    last_match = expected_last in name

    # Wrong-target gate: wrong name -> score=0
    if not (first_match and last_match):
        feedback_parts.append(
            f"Wrong civilian created: expected 'Lamar Davis', got '{civ.get('name')}' "
            f"— wrong-target gate triggered, score zeroed"
        )
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    # Name matches (15 pts)
    score += 15
    feedback_parts.append(f"Civilian name matches: {civ.get('name')}")

    # DOB check (7 pts)
    dob = (civ.get('dob') or '').strip()
    if expected_dob in dob or (
        '1988' in dob and
        any(m in dob for m in ['09', '-9-', '/9/', '9/']) and
        any(d in dob for d in ['05', '-5-', '/5/', '/05', '5/'])
    ):
        score += 7
        feedback_parts.append(f"DOB matches: {dob}")
    else:
        feedback_parts.append(f"DOB mismatch: expected '{expected_dob}', got '{dob}'")

    # Gender check (3 pts)
    gender = (civ.get('gender') or '').strip().lower()
    if 'male' in gender:
        score += 3
        feedback_parts.append(f"Gender matches: {civ.get('gender')}")
    else:
        feedback_parts.append(f"Gender mismatch: expected 'Male', got '{civ.get('gender')}'")

    # === SECTION 2: VEHICLE REGISTRATION (35 pts) ===
    if not result.get('vehicle_found'):
        feedback_parts.append("No vehicle registration found in database")
    else:
        veh = result.get('vehicle', {})
        score += 10
        feedback_parts.append("Vehicle registration created")

        actual_plate = (veh.get('plate') or '').upper().replace('-', '').replace(' ', '')
        if expected_plate in actual_plate or ('LAM' in actual_plate and '8844' in actual_plate):
            score += 15
            feedback_parts.append(f"Vehicle plate matches: {veh.get('plate')}")
        elif 'LAM' in actual_plate:
            score += 7
            feedback_parts.append(f"Vehicle plate partial match: {veh.get('plate')}")
        else:
            feedback_parts.append(f"Vehicle plate mismatch: expected 'LAM-8844', got '{veh.get('plate')}'")

        if result.get('vehicle_linked_to_civilian'):
            score += 10
            feedback_parts.append("Vehicle correctly linked to Lamar Davis identity")
        else:
            feedback_parts.append("Vehicle not linked to Lamar Davis identity (name_id mismatch)")

    # === SECTION 3: WARRANT (40 pts) ===
    if not result.get('warrant_found'):
        feedback_parts.append("No warrant found in database")
    else:
        warrant = result.get('warrant', {})
        score += 15
        feedback_parts.append("Warrant created")

        warrant_name = (warrant.get('warrant_name') or '').lower()
        if 'stolen property' in warrant_name or ('stolen' in warrant_name and 'property' in warrant_name):
            score += 15
            feedback_parts.append(f"Warrant name matches: {warrant.get('warrant_name')}")
        elif 'receiving' in warrant_name or 'stolen' in warrant_name:
            score += 8
            feedback_parts.append(f"Warrant name partial match: {warrant.get('warrant_name')}")
        elif warrant_name:
            score += 3
            feedback_parts.append(f"Warrant name does not match 'Receiving Stolen Property': {warrant.get('warrant_name')}")
        else:
            feedback_parts.append("Warrant name is empty")

        agency = (warrant.get('issuing_agency') or '').lower()
        if 'blaine' in agency or 'sheriff' in agency:
            score += 10
            feedback_parts.append(f"Issuing agency matches: {warrant.get('issuing_agency')}")
        else:
            feedback_parts.append(f"Issuing agency mismatch: expected 'Blaine County Sheriff Office', got '{warrant.get('issuing_agency')}'")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
