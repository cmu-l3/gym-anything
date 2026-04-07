#!/usr/bin/env python3
"""Verifier for Create Custom Profile Fields task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_custom_profile_fields(traj, env_info, task_info):
    """
    Verify that the user profile fields were created correctly.

    Scoring (100 points):
    - Category "Employee Information" exists (10 pts)
    - Field "employeeid" exists, text type, required, locked (30 pts)
    - Field "department" exists, menu type, required, correct options (30 pts)
    - Field "joblevel" exists, text type, default value correct (20 pts)
    - All fields assigned to the correct category (10 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_custom_profile_fields_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Verify Category
        cat_id = str(result.get('category_id', '0'))
        if result.get('category_found', False) and cat_id != '0':
            score += 10
            feedback_parts.append("Category 'Employee Information' created")
        else:
            feedback_parts.append("Category 'Employee Information' NOT found")

        fields = result.get('fields', {})
        eid = fields.get('employeeid')
        dept = fields.get('department')
        job = fields.get('joblevel')

        # 2. Verify Employee ID Field
        if eid:
            # Existence & Type (10)
            if eid.get('datatype') == 'text':
                score += 10
                feedback_parts.append("Field 'employeeid' correct type")
            else:
                feedback_parts.append(f"Field 'employeeid' wrong type: {eid.get('datatype')}")
            
            # Required (10)
            if int(eid.get('required', 0)) == 1:
                score += 10
            else:
                feedback_parts.append("Field 'employeeid' not required")

            # Locked (10)
            if int(eid.get('locked', 0)) == 1:
                score += 10
            else:
                feedback_parts.append("Field 'employeeid' not locked")
        else:
            feedback_parts.append("Field 'employeeid' not found")

        # 3. Verify Department Field
        if dept:
            # Existence & Type (10)
            if dept.get('datatype') == 'menu':
                score += 10
                feedback_parts.append("Field 'department' correct type")
            else:
                feedback_parts.append(f"Field 'department' wrong type: {dept.get('datatype')}")

            # Required (5)
            if int(dept.get('required', 0)) == 1:
                score += 5
            else:
                feedback_parts.append("Field 'department' not required")
            
            # Menu Options (15)
            options = dept.get('param1', '')
            required_opts = ["Emergency Medicine", "Cardiology", "Nursing", "Pediatrics", "Radiology", "Surgery", "Administration"]
            found_opts = 0
            for opt in required_opts:
                if opt in options:
                    found_opts += 1
            
            if found_opts == len(required_opts):
                score += 15
                feedback_parts.append("All department options present")
            elif found_opts >= 4:
                score += 7
                feedback_parts.append(f"Partial department options ({found_opts}/{len(required_opts)})")
            else:
                feedback_parts.append("Department options missing or incorrect")
        else:
            feedback_parts.append("Field 'department' not found")

        # 4. Verify Job Level Field
        if job:
            # Existence & Type (10)
            if job.get('datatype') == 'text':
                score += 10
                feedback_parts.append("Field 'joblevel' correct type")
            else:
                feedback_parts.append(f"Field 'joblevel' wrong type: {job.get('datatype')}")

            # Default Value (10)
            default_val = job.get('defaultdata', '')
            if default_val == "Staff":
                score += 10
            else:
                feedback_parts.append(f"Field 'joblevel' wrong default: '{default_val}'")
        else:
            feedback_parts.append("Field 'joblevel' not found")

        # 5. Verify Category Assignment (10)
        # All 3 fields must be in the created category
        if cat_id != '0' and eid and dept and job:
            if (str(eid.get('categoryid')) == cat_id and 
                str(dept.get('categoryid')) == cat_id and 
                str(job.get('categoryid')) == cat_id):
                score += 10
                feedback_parts.append("All fields in correct category")
            else:
                feedback_parts.append("Some fields in wrong category")
        
        # Anti-gaming check: Ensure counts actually increased
        initial_fields = int(result.get('initial_field_count', 0))
        current_fields = int(result.get('current_field_count', 0))
        if current_fields <= initial_fields and score > 0:
            feedback_parts.append("WARNING: No new fields detected (counts unchanged)")
            # Penalize gaming attempt? Or just rely on precise matching which likely fails if not new.
            # In this case, the 'delete' in setup_task.sh ensures we start clean, so finding them means they were created.
        
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}