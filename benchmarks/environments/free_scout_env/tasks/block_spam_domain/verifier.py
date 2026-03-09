#!/usr/bin/env python3
"""Verifier for block_spam_domain task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_block_spam_domain(traj, env_info, task_info):
    """
    Verify that the phishing domain was blocked in the System Blacklist.
    
    Criteria:
    1. A blacklist rule exists for the specific domain (40 pts)
    2. The rule uses the correct wildcard format '*@domain.com' (30 pts)
    3. The rule contains the requested note/reason (20 pts)
    4. The rule was created during the task session (anti-gaming) (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_domain = metadata.get('target_domain', 'network-security-update.io')
    expected_rule_value = metadata.get('expected_rule_value', f'*@{target_domain}')
    
    # Copy result file from container
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
            
    score = 0
    feedback_parts = []
    
    rule_found = result.get('rule_found', False)
    rule_value = result.get('rule_value', '').strip()
    rule_note = result.get('rule_note', '').lower()
    created_during_task = result.get('rule_created_during_task', False)
    
    # Criterion 1: Rule Found (40 pts)
    if rule_found:
        score += 40
        feedback_parts.append("Blacklist rule found")
    else:
        feedback_parts.append("No blacklist rule found for the target domain")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
        
    # Criterion 2: Correct Format (30 pts)
    # Strictly expect '*@domain' as per instructions, but give partial for just 'domain' or '@domain'
    if rule_value == expected_rule_value:
        score += 30
        feedback_parts.append(f"Correct wildcard format: '{rule_value}'")
    elif target_domain in rule_value:
        score += 15
        feedback_parts.append(f"Partial credit: Domain blocked '{rule_value}' but incorrect wildcard format (expected '{expected_rule_value}')")
    else:
        feedback_parts.append(f"Incorrect rule value: '{rule_value}'")

    # Criterion 3: Note Content (20 pts)
    # Expect "phishing" or "march 2026"
    if "phishing" in rule_note:
        score += 20
        feedback_parts.append("Note correctly identifies 'phishing'")
    elif "march" in rule_note or "campaign" in rule_note:
        score += 10
        feedback_parts.append("Note contains partial details")
    else:
        feedback_parts.append(f"Note missing required details (found: '{rule_note}')")

    # Criterion 4: Timestamp (10 pts)
    if created_during_task:
        score += 10
        feedback_parts.append("Rule created during task session")
    else:
        feedback_parts.append("FAIL: Rule timestamp indicates it was not created during this session")
        # If the rule was old, we penalize significantly to prevent 'do nothing' if cleanup failed
        # But setup script clears it, so this implies the script found a different old rule or clock drift
        score = 0 

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }