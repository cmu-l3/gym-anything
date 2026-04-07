#!/usr/bin/env python3
"""
Verifier for Create Dynamic Email Template task.

Verifies:
1. Template record exists in DB.
2. Subject matches expected.
3. Module matches 'Contacts'.
4. Body contains static text.
5. Body contains dynamic Vtiger merge tags (anti-gaming: agent must not hardcode names).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_email_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', 'Following up on our demonstration')
    expected_module = metadata.get('expected_module', 'Contacts')
    static_text = metadata.get('static_text', 'Thank you for attending our product demonstration today')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_email_template_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    template_found = result.get('template_found', False)
    
    if not template_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: 'Standard Post-Demo Follow-up' template not found in the database."
        }
        
    score += 20
    feedback_parts.append("Template record found")
    
    # 2. Check Subject
    actual_subject = result.get('subject', '')
    if expected_subject.lower() in actual_subject.lower():
        score += 15
        feedback_parts.append("Subject is correct")
    else:
        feedback_parts.append(f"Subject mismatch: expected '{expected_subject}', got '{actual_subject}'")

    # 3. Check Module
    actual_module = result.get('module', '')
    if actual_module.lower() == expected_module.lower():
        score += 10
        feedback_parts.append("Target module is correct")
    else:
        feedback_parts.append(f"Module mismatch: expected '{expected_module}', got '{actual_module}'")

    # 4. Check Static Body Text
    body = result.get('body', '')
    # Normalize spaces/newlines for comparison
    normalized_body = re.sub(r'\s+', ' ', body).replace('&nbsp;', ' ')
    
    if static_text.lower() in normalized_body.lower():
        score += 25
        feedback_parts.append("Static body text correct")
    else:
        feedback_parts.append("Missing core static text in body")

    # 5. Check Dynamic Variables (Anti-gaming check)
    # Vtiger variables typically look like $contacts-firstname$ or $users-phone_work$
    dynamic_vars = re.findall(r'\$[a-zA-Z0-9_]+-[a-zA-Z0-9_]+\$', body)
    unique_vars = set([v.lower() for v in dynamic_vars])
    
    if len(unique_vars) >= 3:
        score += 30
        feedback_parts.append(f"Used {len(unique_vars)} dynamic variables correctly")
    elif len(unique_vars) > 0:
        score += 15
        feedback_parts.append(f"Used only {len(unique_vars)} dynamic variables (expected at least 3)")
    else:
        feedback_parts.append("FAIL: No dynamic variables found. Bracketed text was likely typed literally.")

    # Determine passing logic
    # Must have found the template, and MUST have used at least 1 dynamic variable
    key_criteria_met = template_found and len(unique_vars) > 0
    passed = (score >= 70) and key_criteria_met
    
    if template_found and len(unique_vars) == 0:
        passed = False
        feedback_parts.append("CRITICAL FAILURE: Agent hardcoded names instead of using dynamic merge tags.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }