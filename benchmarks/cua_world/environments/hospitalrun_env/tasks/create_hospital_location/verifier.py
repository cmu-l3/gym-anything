#!/usr/bin/env python3
"""
Verifier for create_hospital_location task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_location(traj, env_info, task_info):
    """
    Verify that the location 'Cardiology Outpatient Center' was created in CouchDB.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Cardiology Outpatient Center")

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    doc_found = result.get('doc_found', False)
    document = result.get('document', {})
    
    if doc_found:
        actual_name = document.get('name', '')
        if actual_name == expected_name:
            score = 100
            feedback_parts.append(f"Location '{actual_name}' successfully created.")
        else:
            # Should not happen given the export script logic, but safe to check
            score = 50
            feedback_parts.append(f"Document found but name mismatch: '{actual_name}' vs '{expected_name}'.")
    else:
        score = 0
        feedback_parts.append(f"No location named '{expected_name}' found in the database.")

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }