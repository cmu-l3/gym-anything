#!/usr/bin/env python3
"""Verifier for create_dispatch_call task."""

import json
import tempfile
import os


def verify_create_dispatch_call(traj, env_info, task_info):
    """Verify a dispatch call was created in OpenCAD."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_call_type = metadata.get('expected_call_type', '10-50')
    expected_street1 = metadata.get('expected_street1', 'Vinewood Boulevard').lower()
    expected_street2 = metadata.get('expected_street2', 'Alta Street').lower()
    expected_keywords = metadata.get('expected_narrative_keywords', [])

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_dispatch_call_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Check 1: Call was found in database (20 pts)
    if result.get('call_found'):
        score += 20
        feedback_parts.append("Call found in database")
    else:
        feedback_parts.append("No dispatch call found in database")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    call = result.get('call', {})

    # Check 2: Call type matches (20 pts)
    call_type = call.get('type', '')
    if expected_call_type in call_type:
        score += 20
        feedback_parts.append(f"Call type matches: {call_type}")
    else:
        feedback_parts.append(f"Call type mismatch: expected '{expected_call_type}', got '{call_type}'")

    # Check 3: Street 1 contains expected street (15 pts)
    street1 = (call.get('street1') or '').lower()
    if expected_street1 in street1:
        score += 15
        feedback_parts.append(f"Street 1 matches: {call.get('street1')}")
    elif 'vinewood' in street1 and 'boulevard' in street1:
        score += 10
        feedback_parts.append(f"Street 1 partial match: {call.get('street1')}")
    else:
        feedback_parts.append(f"Street 1 mismatch: expected '{expected_street1}', got '{street1}'")

    # Check 4: Street 2 contains expected street (15 pts)
    street2 = (call.get('street2') or '').lower()
    if expected_street2 in street2:
        score += 15
        feedback_parts.append(f"Street 2 matches: {call.get('street2')}")
    elif 'alta' in street2 and 'street' in street2:
        score += 10
        feedback_parts.append(f"Street 2 partial match: {call.get('street2')}")
    else:
        feedback_parts.append(f"Street 2 mismatch: expected '{expected_street2}', got '{street2}'")

    # Check 5: Narrative contains expected keywords (20 pts)
    narrative = (call.get('narrative') or '').lower()
    primary = (call.get('primary') or '').lower()
    combined_text = narrative + ' ' + primary
    matched_keywords = []
    for kw in expected_keywords:
        if kw.lower() in combined_text:
            matched_keywords.append(kw)

    if len(expected_keywords) > 0:
        keyword_ratio = len(matched_keywords) / len(expected_keywords)
        keyword_score = int(20 * keyword_ratio)
        score += keyword_score
        feedback_parts.append(f"Narrative keywords: {len(matched_keywords)}/{len(expected_keywords)} matched")
    else:
        score += 20

    # Check 6: New call was actually created (10 pts)
    initial = result.get('initial_call_count', 0)
    current = result.get('current_call_count', 0)
    if current > initial:
        score += 10
        feedback_parts.append("New call record confirmed")
    else:
        feedback_parts.append("No new call records detected")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
