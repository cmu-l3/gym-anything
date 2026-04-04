#!/usr/bin/env python3
"""
Verifier for record_surgical_outcome task.
"""

import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_surgical_outcome(traj, env_info, task_info):
    """
    Verifies that the operative plan was updated to 'Completed' with correct notes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result from Container
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    plan_data = result.get('plan_data', {})
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback = []

    # 2. Verify Document Existence
    if not plan_data.get('exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "The operative plan document was not found in the database."
        }
    
    # 3. Verify Anti-Gaming (Modification happened)
    current_rev = plan_data.get('rev', '')
    initial_rev = plan_data.get('initial_rev', '')
    
    if current_rev == initial_rev:
        return {
            "passed": False,
            "score": 0,
            "feedback": "The record was not modified (database revision matches initial state). Agent did nothing."
        }
    score += 10 # Modified something

    # 4. Verify Status (40 points)
    # HospitalRun status usually: 'Planned', 'Completed', 'Canceled'
    current_status = plan_data.get('status', '')
    expected_statuses = metadata.get('expected_status', ['Completed'])
    
    # Case-insensitive check
    status_match = any(s.lower() == current_status.lower() for s in expected_statuses)
    
    if status_match:
        score += 40
        feedback.append(f"Status correctly updated to '{current_status}'.")
    else:
        feedback.append(f"Incorrect status: expected 'Completed', got '{current_status}'.")

    # 5. Verify Notes Content (50 points)
    current_notes = plan_data.get('notes', '')
    keywords = metadata.get('expected_notes_keywords', [])
    
    found_keywords = 0
    missing_keywords = []
    
    for kw in keywords:
        if kw.lower() in current_notes.lower():
            found_keywords += 1
        else:
            missing_keywords.append(kw)
    
    # Calculate notes score proportionally
    # Total 4 keywords = 50 points -> 12.5 pts each
    notes_score = 0
    if len(keywords) > 0:
        notes_score = (found_keywords / len(keywords)) * 50
    score += notes_score
    
    if len(missing_keywords) == 0:
        feedback.append("All note details recorded correctly.")
    else:
        feedback.append(f"Missing details in notes: {', '.join(missing_keywords)}.")

    # 6. Final Assessment
    # Must have status updated and at least some notes to pass
    passed = (status_match and found_keywords >= 2)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }