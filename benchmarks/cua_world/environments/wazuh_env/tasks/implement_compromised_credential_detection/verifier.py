#!/usr/bin/env python3
"""
Verifier for implement_compromised_credential_detection task.
"""

import json
import os
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compromised_credential_detection(traj, env_info, task_info):
    """
    Verify the compromised credential detection task.
    
    Criteria:
    1. CDB source file exists and has correct key:value format.
    2. CDB binary file exists (compilation successful).
    3. ossec.conf references the list.
    4. Rule 100050 exists.
    5. Logic Test: Rule fires for compromised user.
    6. Logic Test: Rule does NOT fire for safe user.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. Check Source File (10 pts)
    if result.get('source_exists'):
        score += 10
        feedback_parts.append("Source list file created.")
        
        # Verify content format (key:value)
        try:
            content = base64.b64decode(result.get('source_content_b64', '')).decode('utf-8')
            if "admin:compromised" in content or "admin:" in content:
                score += 5
                feedback_parts.append("Source list format looks correct.")
            else:
                feedback_parts.append("Source list missing expected 'admin:value' format.")
        except:
            pass
    else:
        feedback_parts.append("Source list file NOT found.")

    # 2. Check CDB Compilation (20 pts)
    if result.get('cdb_exists'):
        score += 20
        feedback_parts.append("CDB binary file compiled.")
    else:
        feedback_parts.append("CDB binary file NOT found (did you run ossec-makelists?).")

    # 3. Check Configuration (15 pts)
    if result.get('config_contains_list'):
        score += 15
        feedback_parts.append("ossec.conf configured correctly.")
    else:
        feedback_parts.append("ossec.conf does not reference the new list.")

    # 4. Check Rule Existence (10 pts)
    rules_content = base64.b64decode(result.get('rules_content_b64', '')).decode('utf-8')
    if 'id="100050"' in rules_content:
        score += 10
        feedback_parts.append("Rule 100050 found.")
    else:
        feedback_parts.append("Rule 100050 NOT found in local_rules.xml.")

    # 5. Logic Tests (40 pts)
    logic = result.get('logic_test', {})
    
    # Positive Test: Compromised user triggers rule (20 pts)
    if logic.get('positive_triggered'):
        score += 20
        feedback_parts.append("SUCCESS: Rule triggered for compromised user.")
    else:
        feedback_parts.append("FAIL: Rule did NOT trigger for compromised user.")

    # Negative Test: Safe user does NOT trigger rule (20 pts)
    # We also check that the parent rule triggered to ensure the system is working at all
    if not logic.get('negative_triggered') and logic.get('parent_triggered'):
        score += 20
        feedback_parts.append("SUCCESS: Rule correctly ignored safe user.")
    elif logic.get('negative_triggered'):
        feedback_parts.append("FAIL: Rule triggered False Positive for safe user.")
    else:
        feedback_parts.append("FAIL: System did not process safe user log (parent rule 5715 missed).")

    return {
        "passed": score >= 70 and logic.get('positive_triggered'),
        "score": score,
        "feedback": " ".join(feedback_parts)
    }