#!/usr/bin/env python3
"""
Verifier for configure_cost_centers task.

Checks:
1. Three specific Cost Centers exist (Name + Code).
2. Three specific Departments are linked to the correct Cost Centers.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_cost_centers(traj, env_info, task_info):
    """
    Verify that cost centers were created and linked to departments.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected configuration from metadata
    metadata = task_info.get('metadata', {})
    expected_config = metadata.get('expected_ccs', [
        {"name": "Engineering CC", "code": "CC-ENG-01", "dept": "Engineering"},
        {"name": "Sales CC", "code": "CC-SAL-01", "dept": "Sales"},
        {"name": "Marketing CC", "code": "CC-MKT-01", "dept": "Marketing"}
    ])

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    found_ccs = result.get('cost_centers_found', [])
    dept_links = result.get('department_links', [])

    # Map for easy lookup
    cc_map = {item['name']: item for item in found_ccs}
    link_map = {item['department']: item['linked_cc'] for item in dept_links}

    # 1. Verify Cost Center Creation (50 points total)
    #    - 30 pts for existence (10 each)
    #    - 20 pts for correct codes (approx 6.6 each)
    
    cc_score = 0
    for item in expected_config:
        name = item['name']
        expected_code = item['code']
        
        if name in cc_map:
            cc_score += 10
            actual_code = cc_map[name].get('code', '')
            if actual_code == expected_code:
                cc_score += 6.66
            else:
                feedback_parts.append(f"CC '{name}' has wrong code: '{actual_code}' (expected '{expected_code}')")
        else:
            feedback_parts.append(f"Cost Center '{name}' NOT found")

    score += min(50, int(cc_score))

    # 2. Verify Department Associations (45 points total)
    #    - 15 pts per correct link
    
    link_score = 0
    for item in expected_config:
        dept = item['dept']
        expected_cc_name = item['name']
        
        actual_linked_cc = link_map.get(dept)
        
        if actual_linked_cc == expected_cc_name:
            link_score += 15
        elif actual_linked_cc == "null" or not actual_linked_cc:
            feedback_parts.append(f"Department '{dept}' is not linked to any Cost Center")
        else:
            feedback_parts.append(f"Department '{dept}' linked to wrong CC: '{actual_linked_cc}'")

    score += link_score

    # 3. Clean Execution (5 points)
    # Check if extra cost centers were created (simple check based on count)
    if len(found_ccs) == len(expected_config):
        score += 5
    elif len(found_ccs) > len(expected_config):
        feedback_parts.append("Note: More cost centers found than expected (possible duplicates)")

    # Final tally
    passed = score >= 70  # Threshold requiring at least creation + most links
    
    if not feedback_parts:
        feedback_parts.append("All Cost Centers created and linked correctly.")

    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": "; ".join(feedback_parts)
    }