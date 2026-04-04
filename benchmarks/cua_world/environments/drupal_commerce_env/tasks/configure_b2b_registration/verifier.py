#!/usr/bin/env python3
"""
Verifier for configure_b2b_registration task.

Scoring (100 points):
1. Public registration enabled (15 pts)
2. Company Name field exists (15 pts)
3. Tax ID field exists (15 pts)
4. Fields enabled on Register form (20 pts)
5. Test User 'b2b_user' exists (10 pts)
6. Company Name data saved correctly (15 pts)
7. Tax ID data saved correctly (10 pts)

Pass threshold: 70 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_b2b_registration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_company = metadata.get('test_user_company', 'TechCorp')
    expected_tax = metadata.get('test_user_tax_id', 'TX-998877')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Public registration enabled (15 pts)
    # Drupal store 'visitors' for public registration
    reg_access = result.get('register_access', '')
    if reg_access == 'visitors':
        score += 15
        feedback_parts.append("Public registration enabled")
    else:
        feedback_parts.append(f"Public registration NOT enabled (current setting: {reg_access})")

    # 2. Company Name field exists (15 pts)
    has_company_table = str(result.get('has_company_table', 'false')).lower() == 'true'
    if has_company_table:
        score += 15
        feedback_parts.append("Company Name field created")
    else:
        feedback_parts.append("Company Name field missing")

    # 3. Tax ID field exists (15 pts)
    has_tax_table = str(result.get('has_tax_table', 'false')).lower() == 'true'
    if has_tax_table:
        score += 15
        feedback_parts.append("Tax ID field created")
    else:
        feedback_parts.append("Tax ID field missing")

    # 4. Fields enabled on Register form (20 pts)
    # Both must be present for full points, or partial
    company_on_form = str(result.get('company_on_form', 'false')).lower() == 'true'
    tax_on_form = str(result.get('tax_on_form', 'false')).lower() == 'true'
    
    if company_on_form and tax_on_form:
        score += 20
        feedback_parts.append("Both fields enabled on Register form")
    elif company_on_form or tax_on_form:
        score += 10
        feedback_parts.append("Only one field enabled on Register form")
    else:
        feedback_parts.append("Fields not enabled on Register form")

    # 5. Test User Created (10 pts)
    user_exists = str(result.get('test_user_exists', 'false')).lower() == 'true'
    if user_exists:
        score += 10
        feedback_parts.append("Test user 'b2b_user' created")
    else:
        feedback_parts.append("Test user 'b2b_user' NOT found")

    # 6. Company Name Data Saved (15 pts)
    user_company = result.get('user_company_value', '')
    if user_exists and user_company.strip() == expected_company:
        score += 15
        feedback_parts.append(f"Company Name '{expected_company}' saved correctly")
    elif user_exists:
        feedback_parts.append(f"Company Name mismatch: expected '{expected_company}', got '{user_company}'")

    # 7. Tax ID Data Saved (10 pts)
    user_tax = result.get('user_tax_value', '')
    if user_exists and user_tax.strip() == expected_tax:
        score += 10
        feedback_parts.append(f"Tax ID '{expected_tax}' saved correctly")
    elif user_exists:
        feedback_parts.append(f"Tax ID mismatch: expected '{expected_tax}', got '{user_tax}'")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }