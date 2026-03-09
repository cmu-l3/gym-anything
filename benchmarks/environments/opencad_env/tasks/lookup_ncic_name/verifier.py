#!/usr/bin/env python3
"""Verifier for lookup_ncic_name task."""

import json
import tempfile
import os


def verify_lookup_ncic_name(traj, env_info, task_info):
    """Verify NCIC name lookup and citation issuance for Trevor Philips."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_citation = metadata.get('expected_citation', 'Reckless Driving').lower()
    expected_fine = float(metadata.get('expected_fine', 350.00))

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/lookup_ncic_name_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Check 1: Citation was found (30 pts)
    if result.get('citation_found'):
        score += 30
        feedback_parts.append("Citation record found in database")
    else:
        feedback_parts.append("No citation record found")
        return {
            "passed": False,
            "score": score,
            "feedback": ". ".join(feedback_parts)
        }

    citation = result.get('citation', {})

    # Check 2: Citation is for the right person (name_id=3 for Trevor) (15 pts)
    name_id = str(citation.get('name_id', '')).strip()
    if name_id == '3':
        score += 15
        feedback_parts.append("Citation correctly linked to Trevor Philips")
    else:
        feedback_parts.append(f"Citation linked to wrong person (name_id={name_id}, expected 3)")

    # Check 3: Citation type matches (25 pts)
    citation_name = (citation.get('citation_name') or '').lower()
    if 'reckless' in citation_name:
        score += 25
        feedback_parts.append(f"Citation type matches: {citation.get('citation_name')}")
    elif citation_name:
        score += 5
        feedback_parts.append(f"Citation type partial: {citation.get('citation_name')}")
    else:
        feedback_parts.append("Citation type empty")

    # Check 4: Fine amount matches (15 pts)
    try:
        actual_fine = float(citation.get('fine', 0))
        if abs(actual_fine - expected_fine) < 0.01:
            score += 15
            feedback_parts.append(f"Fine matches: ${actual_fine:.2f}")
        elif actual_fine > 0:
            score += 5
            feedback_parts.append(f"Fine mismatch: expected ${expected_fine:.2f}, got ${actual_fine:.2f}")
        else:
            feedback_parts.append("No fine recorded")
    except (ValueError, TypeError):
        feedback_parts.append(f"Invalid fine value: {citation.get('fine')}")

    # Check 5: New citation was created (15 pts)
    initial_count = result.get('initial_trevor_citation_count', 0)
    current_count = result.get('current_trevor_citation_count', 0)
    initial_total = result.get('initial_total_citation_count', 0)
    current_total = result.get('current_total_citation_count', 0)
    if current_count > initial_count or current_total > initial_total:
        score += 15
        feedback_parts.append("New citation record confirmed")
    else:
        feedback_parts.append("No new citation records detected")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
