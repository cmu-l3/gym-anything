#!/usr/bin/env python3
"""
Verifier for customize_email_template task.

Checks:
1. Sales Invoice email template exists.
2. Subject matches expected string with placeholder.
3. Body contains expected snippets and placeholders.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_email_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', 'Invoice {{Reference}} from Northwind Traders')
    expected_body_snippets = metadata.get('expected_body_snippets', [])
    required_placeholders = metadata.get('required_placeholders', [])

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

    # Check for script errors
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Template Exists (30 pts)
    if result.get("template_found", False):
        score += 30
        feedback.append("Sales Invoice template found.")
    else:
        feedback.append("Sales Invoice template NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Subject Verification (30 pts)
    # Check exact match for strictness, or containment
    actual_subject = result.get("subject", "").strip()
    if actual_subject == expected_subject:
        score += 30
        feedback.append("Subject matches exactly.")
    else:
        # Partial credit if placeholders are present but text is slightly off
        if "{{Reference}}" in actual_subject and "Northwind" in actual_subject:
            score += 15
            feedback.append(f"Subject partial match. Expected: '{expected_subject}', Got: '{actual_subject}'")
        else:
            feedback.append(f"Subject incorrect. Got: '{actual_subject}'")

    # 3. Body Verification (40 pts)
    actual_body = result.get("body", "")
    body_score = 0
    
    # Check for snippets
    snippets_found = 0
    for snippet in expected_body_snippets:
        if snippet in actual_body:
            snippets_found += 1
    
    # Check for placeholders specifically
    placeholders_found = 0
    for ph in required_placeholders:
        if ph in actual_body:
            placeholders_found += 1
            
    # Logic: 
    # 20 pts for text snippets
    # 20 pts for placeholders
    
    if len(expected_body_snippets) > 0:
        body_score += 20 * (snippets_found / len(expected_body_snippets))
    
    if len(required_placeholders) > 0:
        body_score += 20 * (placeholders_found / len(required_placeholders))
        
    score += body_score
    
    if body_score == 40:
        feedback.append("Body content correct.")
    else:
        feedback.append(f"Body content issues. Found {snippets_found}/{len(expected_body_snippets)} phrases and {placeholders_found}/{len(required_placeholders)} placeholders.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback),
        "details": {
            "actual_subject": actual_subject,
            "actual_body": actual_body
        }
    }