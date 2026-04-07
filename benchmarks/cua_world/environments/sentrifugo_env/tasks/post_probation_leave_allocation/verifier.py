#!/usr/bin/env python3
"""
Verifier for post_probation_leave_allocation task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_probation_leave_allocation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy exported allocation result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/post_probation_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    allocations = result.get('allocations', [])
    
    # Read expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_allocs = metadata.get('expected_allocations', [])
    skipped_emp = metadata.get('skipped_employee', 'EMP013')

    score = 0
    feedback_parts = []
    
    # 1. Evaluate expected allocations (15 pts per correct allocation)
    for exp in expected_allocs:
        empid = exp['empid']
        leavetype = exp['leavetype']
        exp_days = float(exp['days'])
        
        # Find matching DB record mapped by user/leavetype
        matches = [a for a in allocations if a['empid'] == empid and 
                   (a['leavetype'] and leavetype.lower() in a['leavetype'].lower())]
        
        if not matches:
            feedback_parts.append(f"{empid} {leavetype}: Not found (0/15)")
        else:
            match = matches[0]
            # Precise match check for exact days
            if abs(match['days'] - exp_days) < 0.1:
                score += 15
                feedback_parts.append(f"{empid} {leavetype}: Correct ({exp_days} days) (15/15)")
            else:
                # Detect the anti-pattern: Did they input hours directly?
                if abs(match['days'] - (exp_days * 8)) < 0.1:
                    feedback_parts.append(f"{empid} {leavetype}: Wrong unit - entered hours instead of days ({match['days']}) (0/15)")
                else:
                    feedback_parts.append(f"{empid} {leavetype}: Wrong days - got {match['days']}, expected {exp_days} (0/15)")
                    
    # 2. Evaluate skipped employee handling (10 pts)
    skipped_matches = [a for a in allocations if a['empid'] == skipped_emp]
    if not skipped_matches:
        score += 10
        feedback_parts.append(f"{skipped_emp}: Correctly skipped (10/10)")
    else:
        feedback_parts.append(f"{skipped_emp}: Incorrectly allocated leave despite memo warning (0/10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }