#!/usr/bin/env python3
"""Verifier for add_citation_type task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_citation_type(traj, env_info, task_info):
    """
    Verify that the 'Equipment Safety Violation' citation type was added.

    Scoring:
    - 50 pts: Citation type exists in database (loose match)
    - 25 pts: Citation type name matches EXACTLY
    - 25 pts: Record count increased (anti-gaming/do-nothing check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_citation_type', 'Equipment Safety Violation')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_citation_type_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    found_entry = result.get('found_entry', {})
    found_name = found_entry.get('name', '')
    
    # Criterion 1: Loose match exists (50 pts)
    if result.get('target_found_loose'):
        score += 50
        feedback_parts.append("Citation type found in database")
    else:
        feedback_parts.append("Citation type NOT found in database")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    # Criterion 2: Exact match (25 pts)
    if result.get('target_found_exact'):
        score += 25
        feedback_parts.append(f"Name matches exactly: '{expected_name}'")
    else:
        feedback_parts.append(f"Name mismatch (partial match only): expected '{expected_name}', got '{found_name}'")

    # Criterion 3: New record / Count increased (25 pts)
    # We check if the found ID is > initial max ID, or if count increased
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    is_new = found_entry.get('is_new_record', False)

    if is_new or current_count > initial_count:
        score += 25
        feedback_parts.append("New record confirmed")
    else:
        feedback_parts.append("No new records detected (database count did not increase)")

    # Pass if score >= 75 (Must have at least found the item and it be a new/correct entry)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }