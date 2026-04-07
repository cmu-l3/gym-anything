#!/usr/bin/env python3
"""
Verifier for reporting_chain_reconfig task.

Evaluates if the agent updated the Reporting Manager correctly for 5 specific employees.
Performs checks against the initial state to prevent do-nothing submissions.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reporting_chain_reconfig(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    actual = result.get('actual', {})
    expected = result.get('expected', {})
    initial = result.get('initial', {})

    score = 0
    feedback_parts = []

    # Anti-gaming: Detect if anything changed
    changed = False
    for empid in actual:
        if actual.get(empid) and actual.get(empid) != initial.get(empid):
            changed = True
            break
            
    if not changed:
        return {"passed": False, "score": 0, "feedback": "No reporting managers were changed from their initial incorrect state."}

    # Evaluate against each employee target
    for empid in ["EMP002", "EMP006", "EMP010", "EMP012", "EMP014"]:
        expected_mgr = expected.get(empid, "")
        actual_mgr = actual.get(empid, "")
        
        if not expected_mgr:
            feedback_parts.append(f"{empid}: Setup error, expected manager ID not found")
            continue
            
        if actual_mgr == expected_mgr:
            score += 20
            feedback_parts.append(f"{empid}: Correctly reassigned (20/20)")
        else:
            feedback_parts.append(f"{empid}: Incorrectly assigned or unchanged (0/20)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }