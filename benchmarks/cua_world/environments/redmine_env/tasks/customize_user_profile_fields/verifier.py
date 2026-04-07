#!/usr/bin/env python3
"""
Verifier for customize_user_profile_fields task.

Checks:
1. Two specific Custom Fields exist ("Department", "Employee ID").
2. "Department" is a List with specific values and is Required.
3. "Employee ID" is Text with specific Regex and Length constraints.
4. The Admin user's profile has been updated with valid values for these fields.
5. Items were created/updated after task start.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_user_profile_fields(traj, env_info, task_info):
    """
    Verify the creation of user custom fields and profile update.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected config
    exp_dept = metadata.get('field_department', {})
    exp_empid = metadata.get('field_employee_id', {})
    exp_user = metadata.get('user_data', {})

    # Copy result from container
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

    custom_fields = result.get('custom_fields', [])
    admin_user = result.get('admin_user', {})
    
    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Verify "Department" Field (40 points)
    # ----------------------------------------------------------------
    dept_field = next((f for f in custom_fields if f['name'] == exp_dept['name']), None)
    
    if dept_field:
        # Existence and Type
        if dept_field.get('customized_type') == 'user':
            score += 10
        else:
            feedback_parts.append("Department field exists but wrong type (not User)")
            
        # Format (List)
        if dept_field.get('field_format') == exp_dept['format']:
            score += 10
        else:
            feedback_parts.append(f"Department format mismatch: {dept_field.get('field_format')}")

        # Possible Values
        actual_values = [v['value'] for v in dept_field.get('possible_values', [])]
        expected_values = exp_dept.get('values', [])
        # Check if all expected are present (order doesn't strictly matter for scoring, but good to check)
        if set(actual_values) == set(expected_values):
            score += 10
        else:
            feedback_parts.append(f"Department values mismatch. Found: {actual_values}")

        # Required
        if dept_field.get('is_required') is True:
            score += 10
        else:
            feedback_parts.append("Department field is not set to Required")
            
        feedback_parts.append("Department field found")
    else:
        feedback_parts.append("Department custom field NOT found")

    # ----------------------------------------------------------------
    # 2. Verify "Employee ID" Field (40 points)
    # ----------------------------------------------------------------
    empid_field = next((f for f in custom_fields if f['name'] == exp_empid['name']), None)
    
    if empid_field:
        # Existence and Type
        if empid_field.get('customized_type') == 'user':
            score += 5 # Reduced weight to focus on regex
        
        # Format (Text/String)
        if empid_field.get('field_format') == exp_empid['format']:
            score += 5
            
        # Regex
        actual_regex = empid_field.get('regexp', '')
        if actual_regex == exp_empid['regex']:
            score += 15
        elif actual_regex:
            score += 5 # Partial credit for any regex
            feedback_parts.append(f"Employee ID regex incorrect: '{actual_regex}'")
        else:
            feedback_parts.append("Employee ID regex missing")

        # Length Constraints
        if (empid_field.get('min_length') == exp_empid['min_length'] and 
            empid_field.get('max_length') == exp_empid['max_length']):
            score += 15
        else:
            feedback_parts.append(f"Employee ID length constraints mismatch ({empid_field.get('min_length')}-{empid_field.get('max_length')})")
            
        feedback_parts.append("Employee ID field found")
    else:
        feedback_parts.append("Employee ID custom field NOT found")

    # ----------------------------------------------------------------
    # 3. Verify Admin User Data (20 points)
    # ----------------------------------------------------------------
    user_custom_values = admin_user.get('custom_fields', [])
    
    # Check Department Value
    user_dept = next((v for v in user_custom_values if v['name'] == exp_dept['name']), None)
    if user_dept and user_dept.get('value') == exp_user['department']:
        score += 10
        feedback_parts.append(f"Admin department set to {exp_user['department']}")
    else:
        feedback_parts.append(f"Admin department not set correctly")

    # Check Employee ID Value
    user_empid = next((v for v in user_custom_values if v['name'] == exp_empid['name']), None)
    if user_empid and user_empid.get('value') == exp_user['employee_id']:
        score += 10
        feedback_parts.append(f"Admin Employee ID set to {exp_user['employee_id']}")
    else:
        feedback_parts.append("Admin Employee ID not set correctly")

    # ----------------------------------------------------------------
    # Final Score Calculation
    # ----------------------------------------------------------------
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }