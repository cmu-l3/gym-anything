#!/usr/bin/env python3
"""Verifier for multi_jurisdiction_pursuit task."""

import json
import tempfile
import os


def verify_multi_jurisdiction_pursuit(traj, env_info, task_info):
    """Verify 10-80 pursuit call, vehicle BOLO, Trevor warrant, and Trevor citation.

    Scoring (100 pts, pass >= 70):
      Section 1 - CAD Call (15 pts, GATE): call must exist or score=0
        - Call type 10-80 / pursuit: 10 pts
        - Street 1 Del Perro Boulevard: 5 pts
      Section 2 - Vehicle BOLO (20 pts):
        - BOLO created: 10 pts
        - Plate contains BLC-4491: 10 pts
      Section 3 - Warrant for Trevor Philips (30 pts, wrong-target gate):
        - Wrong-target gate: warrant exists but NOT for Trevor -> 0 for section
        - Trevor warrant confirmed: 15 pts
        - Warrant name contains 'evad' or 'felony' or 'pursuit': 15 pts
      Section 4 - Citation for Trevor Philips (35 pts, wrong-target gate):
        - Wrong-target gate: citation exists but NOT for Trevor -> 0 for section
        - Trevor citation confirmed: 15 pts
        - Citation name contains 'reckless': 15 pts
        - Fine matches $750.00 (+/- $1.00): 5 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_call_type = metadata.get('expected_call_type', '10-80')
    expected_street1 = metadata.get('expected_street1', 'Del Perro Boulevard').lower()
    expected_plate = metadata.get('expected_vehicle_plate', 'BLC-4491').upper().replace('-', '')
    expected_fine = float(metadata.get('expected_fine', 750.00))

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/multi_jurisdiction_pursuit_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # === SECTION 1: CAD CALL (15 pts) — GATE ===
    if not result.get('call_found'):
        feedback_parts.append("No dispatch call found in database")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    call = result.get('call', {})
    call_type = (call.get('type') or '').lower()
    if expected_call_type.lower() in call_type or '10-80' in call_type or 'pursuit' in call_type or 'chase' in call_type:
        score += 10
        feedback_parts.append(f"Call type matches: {call.get('type')}")
    else:
        feedback_parts.append(f"Call type mismatch: expected '10-80', got '{call.get('type')}'")

    street1 = (call.get('street1') or '').lower()
    if expected_street1 in street1 or 'del perro' in street1 or 'perro' in street1:
        score += 5
        feedback_parts.append(f"Street 1 matches: {call.get('street1')}")
    else:
        feedback_parts.append(f"Street 1 mismatch: expected '{expected_street1}', got '{street1}'")

    # === SECTION 2: VEHICLE BOLO (20 pts) ===
    if not result.get('vehicle_bolo_found'):
        feedback_parts.append("No vehicle BOLO found in database")
    else:
        veh = result.get('vehicle_bolo', {})
        score += 10
        feedback_parts.append("Vehicle BOLO created")

        actual_plate = (veh.get('plate') or '').upper().replace('-', '').replace(' ', '')
        if expected_plate in actual_plate or ('BLC' in actual_plate and '4491' in actual_plate):
            score += 10
            feedback_parts.append(f"Vehicle BOLO plate matches: {veh.get('plate')}")
        elif 'BLC' in actual_plate:
            score += 5
            feedback_parts.append(f"Vehicle BOLO plate partial match: {veh.get('plate')}")
        else:
            feedback_parts.append(f"Vehicle BOLO plate mismatch: expected 'BLC-4491', got '{veh.get('plate')}'")

    # === SECTION 3: WARRANT FOR TREVOR PHILIPS (30 pts, wrong-target gate) ===
    if not result.get('warrant_found'):
        feedback_parts.append("No warrant found in database")
    else:
        if not result.get('trevor_warrant_found'):
            warrant_name_id = result.get('warrant', {}).get('name_id', '?')
            feedback_parts.append(
                f"Warrant issued for wrong person (name_id={warrant_name_id}, "
                f"expected Trevor Philips name_id=3) — warrant score zeroed"
            )
        else:
            warrant = result.get('warrant', {})
            score += 15
            feedback_parts.append("Warrant correctly linked to Trevor Philips")

            warrant_name = (warrant.get('warrant_name') or '').lower()
            if 'evad' in warrant_name or ('felony' in warrant_name and 'evad' in warrant_name):
                score += 15
                feedback_parts.append(f"Warrant name matches: {warrant.get('warrant_name')}")
            elif 'felony' in warrant_name or 'pursuit' in warrant_name or 'flee' in warrant_name:
                score += 8
                feedback_parts.append(f"Warrant name partial match: {warrant.get('warrant_name')}")
            elif warrant_name:
                score += 3
                feedback_parts.append(f"Warrant name does not match 'Evading Police Officer - Felony': {warrant.get('warrant_name')}")
            else:
                feedback_parts.append("Warrant name is empty")

    # === SECTION 4: CITATION FOR TREVOR PHILIPS (35 pts, wrong-target gate) ===
    if not result.get('citation_found'):
        feedback_parts.append("No citation found in database")
    else:
        if not result.get('trevor_citation_found'):
            citation_name_id = result.get('citation', {}).get('name_id', '?')
            feedback_parts.append(
                f"Citation issued to wrong person (name_id={citation_name_id}, "
                f"expected Trevor Philips name_id=3) — citation score zeroed"
            )
        else:
            citation = result.get('citation', {})
            score += 15
            feedback_parts.append("Citation correctly linked to Trevor Philips")

            citation_name = (citation.get('citation_name') or '').lower()
            if 'reckless driving' in citation_name or ('reckless' in citation_name and 'driv' in citation_name):
                score += 15
                feedback_parts.append(f"Citation name matches: {citation.get('citation_name')}")
            elif 'reckless' in citation_name:
                score += 8
                feedback_parts.append(f"Citation name partial match: {citation.get('citation_name')}")
            elif citation_name:
                score += 3
                feedback_parts.append(f"Citation name does not match 'Reckless Driving': {citation.get('citation_name')}")
            else:
                feedback_parts.append("Citation name is empty")

            # Fine: $750.00 (5 pts)
            try:
                actual_fine = float(citation.get('fine', 0))
                if abs(actual_fine - expected_fine) < 1.00:
                    score += 5
                    feedback_parts.append(f"Fine matches: ${actual_fine:.2f}")
                elif abs(actual_fine - expected_fine) <= 75:
                    score += 2
                    feedback_parts.append(
                        f"Fine close: expected ${expected_fine:.2f}, got ${actual_fine:.2f}"
                    )
                else:
                    feedback_parts.append(
                        f"Fine mismatch: expected ${expected_fine:.2f}, got ${actual_fine:.2f}"
                    )
            except (ValueError, TypeError):
                feedback_parts.append(f"Invalid fine value: {citation.get('fine')}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
