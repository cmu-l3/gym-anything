#!/usr/bin/env python3
"""Verifier for fugitive_traffic_stop task."""

import json
import tempfile
import os


def verify_fugitive_traffic_stop(traj, env_info, task_info):
    """Verify traffic stop call, Franklin Clinton citation, and person BOLO.

    Scoring (100 pts, pass >= 70):
      Section 1 - CAD Call (35 pts, GATE): call must exist or score=0
        - Call type 10-38 / Traffic Stop: 15 pts
        - Street 1 Forum Drive: 10 pts
        - Street 2 Strawberry Avenue: 10 pts
      Section 2 - Citation (45 pts, wrong-target gate):
        - Wrong-target gate: citation exists but NOT for Franklin Clinton -> 0 for section
        - Franklin Clinton citation confirmed: 10 pts
        - Citation name contains 'Red Light': 20 pts
        - Fine matches $175.00 (+/- $0.01): 15 pts
      Section 3 - Person BOLO (20 pts):
        - BOLO created: 10 pts
        - Description contains relevant keywords: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_call_type = metadata.get('expected_call_type', '10-38')
    expected_street1 = metadata.get('expected_street1', 'Forum Drive').lower()
    expected_street2 = metadata.get('expected_street2', 'Strawberry Avenue').lower()
    expected_fine = float(metadata.get('expected_fine', 175.00))

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fugitive_traffic_stop_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # === SECTION 1: CAD CALL (35 pts) — GATE ===
    if not result.get('call_found'):
        feedback_parts.append("No dispatch call found in database")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    call = result.get('call', {})

    # Call type: 10-38 traffic stop (15 pts)
    call_type = (call.get('type') or '').lower()
    if expected_call_type.lower() in call_type or '10-38' in call_type or 'traffic stop' in call_type:
        score += 15
        feedback_parts.append(f"Call type matches: {call.get('type')}")
    else:
        feedback_parts.append(f"Call type mismatch: expected '10-38', got '{call.get('type')}'")

    # Street 1: Forum Drive (10 pts)
    street1 = (call.get('street1') or '').lower()
    if expected_street1 in street1 or 'forum' in street1:
        score += 10
        feedback_parts.append(f"Street 1 matches: {call.get('street1')}")
    else:
        feedback_parts.append(f"Street 1 mismatch: expected '{expected_street1}', got '{street1}'")

    # Street 2: Strawberry Avenue (10 pts)
    street2 = (call.get('street2') or '').lower()
    if expected_street2 in street2 or 'strawberry' in street2:
        score += 10
        feedback_parts.append(f"Street 2 matches: {call.get('street2')}")
    else:
        feedback_parts.append(f"Street 2 mismatch: expected '{expected_street2}', got '{street2}'")

    # === SECTION 2: CITATION FOR FRANKLIN CLINTON (45 pts) ===
    if not result.get('citation_found'):
        feedback_parts.append("No citation found in database")
    else:
        # Wrong-target gate: citation must be for Franklin Clinton (name_id=2)
        if not result.get('franklin_citation_found'):
            citation_name_id = result.get('citation', {}).get('name_id', '?')
            feedback_parts.append(
                f"Citation issued to wrong person (name_id={citation_name_id}, "
                f"expected Franklin Clinton name_id=2) — citation score zeroed"
            )
        else:
            citation = result.get('citation', {})
            # Franklin confirmed (10 pts)
            score += 10
            feedback_parts.append("Citation correctly linked to Franklin Clinton")

            # Citation name (20 pts)
            citation_name = (citation.get('citation_name') or '').lower()
            if 'red light' in citation_name or 'running red' in citation_name:
                score += 20
                feedback_parts.append(f"Citation name matches: {citation.get('citation_name')}")
            elif citation_name:
                score += 5
                feedback_parts.append(f"Citation name partial match: {citation.get('citation_name')}")
            else:
                feedback_parts.append("Citation name is empty")

            # Fine amount (15 pts)
            try:
                actual_fine = float(citation.get('fine', 0))
                if abs(actual_fine - expected_fine) < 0.01:
                    score += 15
                    feedback_parts.append(f"Fine matches: ${actual_fine:.2f}")
                elif abs(actual_fine - expected_fine) <= 25:
                    score += 7
                    feedback_parts.append(
                        f"Fine close match: expected ${expected_fine:.2f}, got ${actual_fine:.2f}"
                    )
                else:
                    feedback_parts.append(
                        f"Fine mismatch: expected ${expected_fine:.2f}, got ${actual_fine:.2f}"
                    )
            except (ValueError, TypeError):
                feedback_parts.append(f"Invalid fine value: {citation.get('fine')}")

    # === SECTION 3: PERSON BOLO (20 pts) ===
    if not result.get('bolo_person_found'):
        feedback_parts.append("No person BOLO found in database")
    else:
        bolo = result.get('bolo_person', {})
        score += 10
        feedback_parts.append("Person BOLO created")

        desc = (bolo.get('physical_description') or '').lower()
        reason = (bolo.get('reason_wanted') or '').lower()
        combined = desc + ' ' + reason
        if any(kw in combined for kw in ['gray', 'grey', 'hoodie', 'black', 'fled', 'fleeing', 'passenger', 'athletic', 'foot']):
            score += 10
            feedback_parts.append("BOLO description contains relevant details about the fleeing passenger")
        else:
            feedback_parts.append("BOLO description lacks specific details about the fleeing passenger")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
