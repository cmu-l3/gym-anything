#!/usr/bin/env python3
"""Verifier for add_street task in OpenCAD."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_street(traj, env_info, task_info):
    """
    Verify that the street 'Quarry Ridge Haul Rd' was added to the database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_street_name', 'Quarry Ridge Haul Rd').lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_street_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    street_found = result.get('street_found', False)
    street_data = result.get('street', {})
    actual_name = (street_data.get('name') or '').strip()
    
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))

    # Criterion 1: Street record exists in database (40 pts)
    if street_found:
        score += 40
        feedback_parts.append("Street record found in database")
    else:
        feedback_parts.append("Street record NOT found in database")
        # Critical failure if record not found
        return {
            "passed": False, 
            "score": score, 
            "feedback": ". ".join(feedback_parts)
        }

    # Criterion 2: Name fidelity (20 pts)
    # Check for exact case-insensitive match
    if actual_name.lower() == expected_name:
        score += 20
        feedback_parts.append(f"Street name matches exactly: '{actual_name}'")
    elif expected_name in actual_name.lower():
        # Partial match (e.g., if they added extra spaces or punctuation)
        score += 10
        feedback_parts.append(f"Street name partial match: '{actual_name}'")
    else:
        feedback_parts.append(f"Street name mismatch: expected '{expected_name}', got '{actual_name}'")

    # Criterion 3: New record created (Count increased) (20 pts)
    if current_count > initial_count:
        score += 20
        feedback_parts.append("Street count increased")
    else:
        feedback_parts.append("Street count did not increase (record might have replaced an old one?)")

    # Criterion 4: Anti-gaming / Freshness (10 pts)
    # The export script filters by ID > baseline, so if street_found is true, 
    # it implies it's a new record. We double check logic here.
    street_id = str(street_data.get('id', '0'))
    baseline_id = int(result.get('baseline_max_id', 0))
    
    if street_id.isdigit() and int(street_id) > baseline_id:
        score += 10
        feedback_parts.append("Confirmed record created during task session")
    else:
        feedback_parts.append("Could not confirm record was created during this session")

    # Criterion 5: App was accessible (10 pts)
    # Basic check that the environment didn't crash
    if result.get('app_accessible') == "200":
        score += 10
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }