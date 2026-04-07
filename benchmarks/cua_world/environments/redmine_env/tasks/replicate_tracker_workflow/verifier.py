#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_replicate_tracker_workflow(traj, env_info, task_info):
    """
    Verifies that the workflow was copied and the specific constraint was applied.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    
    # Check for script errors
    if 'error' in db_state:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification script error: {db_state['error']}"
        }

    # Scoring Criteria
    score = 0
    feedback = []

    # 1. Workflow Populated (40 pts)
    # Checks if ANY transitions exist, implying a copy operation (or manual entry of at least something)
    # Since the source had at least 3 transitions, the target should have similar count minus deletions
    count = db_state.get('total_transitions_count', 0)
    if db_state.get('workflow_populated', False) and count >= 2:
        score += 40
        feedback.append("Workflow populated successfully.")
    else:
        feedback.append(f"Workflow not populated (found {count} transitions).")

    # 2. Constraint Enforced (40 pts)
    # The New -> Approved transition must NOT exist
    if not db_state.get('forbidden_transition_exists', True):
        score += 40
        feedback.append("Safety constraint enforced (New -> Approved disabled).")
    else:
        feedback.append("Safety constraint FAILED (New -> Approved still enabled).")

    # 3. Pathway Preserved (20 pts)
    # The New -> Review transition MUST exist
    if db_state.get('required_transition_exists', False):
        score += 20
        feedback.append("Review pathway preserved (New -> Review enabled).")
    else:
        feedback.append("Review pathway broken (New -> Review disabled).")

    # Final check
    passed = score >= 80  # Requires population + constraint enforcement
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }