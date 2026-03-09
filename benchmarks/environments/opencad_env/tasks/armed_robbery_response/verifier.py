#!/usr/bin/env python3
"""Verifier for armed_robbery_response task."""

import json
import tempfile
import os


def verify_armed_robbery_response(traj, env_info, task_info):
    """Verify 10-31 call, vehicle BOLO, person BOLO, and Trevor warrant.

    Scoring (100 pts, pass >= 70):
      Section 1 - CAD Call (20 pts, GATE): call must exist or score=0
        - Call type 10-31 / armed robbery: 10 pts
        - Street 1 Vinewood Boulevard: 5 pts
        - Street 2 Hawick Avenue: 5 pts
      Section 2 - Vehicle BOLO (25 pts):
        - BOLO created: 10 pts
        - Plate contains RPZ-7851: 15 pts
      Section 3 - Person BOLO (20 pts):
        - BOLO created: 10 pts
        - Description contains relevant keywords: 10 pts
      Section 4 - Warrant for Trevor Philips (35 pts, wrong-target gate):
        - Wrong-target gate: warrant exists but NOT for Trevor -> 0 for section
        - Trevor warrant confirmed: 20 pts
        - Warrant name contains 'robbery' or 'armed': 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_call_type = metadata.get('expected_call_type', '10-31')
    expected_street1 = metadata.get('expected_street1', 'Vinewood Boulevard').lower()
    expected_street2 = metadata.get('expected_street2', 'Hawick Avenue').lower()
    expected_plate = metadata.get('expected_vehicle_plate', 'RPZ-7851').upper().replace('-', '')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/armed_robbery_response_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # === SECTION 1: CAD CALL (20 pts) — GATE ===
    if not result.get('call_found'):
        feedback_parts.append("No dispatch call found in database")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    call = result.get('call', {})
    call_type = (call.get('type') or '').lower()
    if expected_call_type.lower() in call_type or '10-31' in call_type or 'armed robbery' in call_type or 'crime in progress' in call_type:
        score += 10
        feedback_parts.append(f"Call type matches: {call.get('type')}")
    else:
        feedback_parts.append(f"Call type mismatch: expected '10-31', got '{call.get('type')}'")

    street1 = (call.get('street1') or '').lower()
    if expected_street1 in street1 or 'vinewood' in street1:
        score += 5
        feedback_parts.append(f"Street 1 matches: {call.get('street1')}")
    else:
        feedback_parts.append(f"Street 1 mismatch: expected '{expected_street1}', got '{street1}'")

    street2 = (call.get('street2') or '').lower()
    if expected_street2 in street2 or 'hawick' in street2:
        score += 5
        feedback_parts.append(f"Street 2 matches: {call.get('street2')}")
    else:
        feedback_parts.append(f"Street 2 mismatch: expected '{expected_street2}', got '{street2}'")

    # === SECTION 2: VEHICLE BOLO (25 pts) ===
    if not result.get('vehicle_bolo_found'):
        feedback_parts.append("No vehicle BOLO found in database")
    else:
        veh = result.get('vehicle_bolo', {})
        score += 10
        feedback_parts.append("Vehicle BOLO created")

        actual_plate = (veh.get('plate') or '').upper().replace('-', '').replace(' ', '')
        if expected_plate in actual_plate or 'RPZ' in actual_plate:
            score += 15
            feedback_parts.append(f"Vehicle BOLO plate matches: {veh.get('plate')}")
        else:
            feedback_parts.append(f"Vehicle BOLO plate mismatch: expected 'RPZ-7851', got '{veh.get('plate')}'")

    # === SECTION 3: PERSON BOLO (20 pts) ===
    if not result.get('person_bolo_found'):
        feedback_parts.append("No person BOLO found in database")
    else:
        per = result.get('person_bolo', {})
        score += 10
        feedback_parts.append("Person BOLO created")

        desc = (per.get('physical_description') or '').lower()
        reason = (per.get('reason_wanted') or '').lower()
        combined = desc + ' ' + reason
        if any(kw in combined for kw in ['hispanic', 'brown', 'jacket', 'leather', 'robbery', 'suspect', 'male', 'latin']):
            score += 10
            feedback_parts.append("Person BOLO description contains relevant details about suspect")
        else:
            feedback_parts.append("Person BOLO description lacks specific details about the robbery suspect")

    # === SECTION 4: WARRANT FOR TREVOR PHILIPS (35 pts, wrong-target gate) ===
    if not result.get('warrant_found'):
        feedback_parts.append("No warrant found in database")
    else:
        # Wrong-target gate: warrant must be for Trevor Philips (name_id=3)
        if not result.get('trevor_warrant_found'):
            warrant_name_id = result.get('warrant', {}).get('name_id', '?')
            feedback_parts.append(
                f"Warrant issued for wrong person (name_id={warrant_name_id}, "
                f"expected Trevor Philips name_id=3) — warrant score zeroed"
            )
        else:
            warrant = result.get('warrant', {})
            score += 20
            feedback_parts.append("Warrant correctly linked to Trevor Philips")

            warrant_name = (warrant.get('warrant_name') or '').lower()
            if 'armed robbery' in warrant_name or ('robbery' in warrant_name and 'armed' in warrant_name):
                score += 15
                feedback_parts.append(f"Warrant name matches: {warrant.get('warrant_name')}")
            elif 'robbery' in warrant_name or 'armed' in warrant_name:
                score += 8
                feedback_parts.append(f"Warrant name partial match: {warrant.get('warrant_name')}")
            elif warrant_name:
                score += 3
                feedback_parts.append(f"Warrant name does not match 'Armed Robbery': {warrant.get('warrant_name')}")
            else:
                feedback_parts.append("Warrant name is empty")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
