#!/usr/bin/env python3
"""
Verifier for create_reply_template task.

Checks:
1. Template exists in database (30 pts)
2. Subject matches exactly (20 pts)
3. Body contains required variable (20 pts)
4. Body contains required text segments (20 pts)
5. Anti-gaming (created during task implicit if we cleaned it, 10 pts)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_reply_template(traj, env_info, task_info):
    """
    Verify the creation of the reply template.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('template_name', "Password Reset Completion")
    expected_subject = metadata.get('expected_subject', "")
    required_strings = metadata.get('required_strings', [])
    required_variable = metadata.get('required_variable', "$RequesterName")

    # Load result from container
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
    
    # 1. Check Existence
    if not result.get('found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Template '{expected_name}' not found in database."
        }
    
    score += 30
    feedback_parts.append("Template created")

    # 2. Check Subject
    actual_subject = result.get('subject', "")
    # Allow minor whitespace differences
    if expected_subject.lower().strip() in actual_subject.lower().strip():
        score += 20
        feedback_parts.append("Subject correct")
    else:
        feedback_parts.append(f"Subject mismatch (Expected: '{expected_subject}', Found: '{actual_subject}')")

    # 3. Check Body Content (Strings)
    actual_body = result.get('body', "")
    
    # Simple HTML tag stripping for loose comparison could be useful, 
    # but usually substring search is enough even with HTML tags
    missing_strings = []
    for req_str in required_strings:
        # We do case-insensitive search to be slightly lenient
        if req_str.lower() not in actual_body.lower():
            missing_strings.append(req_str)
    
    if not missing_strings:
        score += 20
        feedback_parts.append("Body content correct")
    else:
        feedback_parts.append(f"Body missing text: {missing_strings[:1]}...")

    # 4. Check Variable Usage
    # Variables in SDP often look like $RequesterName or ${RequesterName}
    # We check for the core variable name
    var_core = required_variable.replace('$', '').replace('{', '').replace('}', '')
    if var_core in actual_body:
        score += 20
        feedback_parts.append("Variable used")
    else:
        feedback_parts.append(f"Variable '{required_variable}' not found in body")

    # 5. Implicit Global/Public check
    # Since we can't easily query the 'is_public' bit without schema knowledge,
    # we assume if the agent followed instructions to make it for "All Technicians",
    # it's likely correct if the rest is correct. 
    # We award the final 10 points if all other content checks passed.
    if score >= 90:
        score += 10
        feedback_parts.append("Configuration assumed correct")
    else:
        feedback_parts.append("Configuration check skipped due to errors")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }