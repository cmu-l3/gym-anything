#!/usr/bin/env python3
"""
Verifier for add_new_school task.

Verifies that the agent successfully added "Riverside Academy" with correct details.
"""

import json
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_new_school(traj, env_info, task_info):
    """
    Verify the add_new_school task.
    
    Scoring Criteria:
    1. School record exists (25 pts)
    2. Name matches exactly (15 pts)
    3. Address matches (15 pts)
    4. City matches (10 pts)
    5. State matches (5 pts)
    6. Zip matches (5 pts)
    7. Phone matches (10 pts)
    8. Anti-gaming: Record is new (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load Expected Values from Metadata
    meta = task_info.get('metadata', {})
    exp_title = meta.get('expected_title', 'Riverside Academy')
    exp_address = meta.get('expected_address', '450 River Road')
    exp_city = meta.get('expected_city', 'Springfield')
    exp_state = meta.get('expected_state', 'IL')
    exp_zip = meta.get('expected_zip', '62704')
    exp_phone = meta.get('expected_phone', '217-555-0198')

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize Score
    score = 0
    feedback = []
    
    # 1. Check if record found (25 pts)
    if not result.get('found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No school record found matching 'Riverside'."
        }
    
    score += 25
    feedback.append("School record found.")
    
    school = result.get('school', {})
    
    # Helper for case-insensitive comparison
    def check_field(field_name, expected, points, is_exact=True):
        actual = str(school.get(field_name, '')).strip()
        passed = False
        if is_exact:
            if actual.lower() == expected.lower():
                passed = True
        else:
            if expected.lower() in actual.lower():
                passed = True
        
        if passed:
            return points, f"{field_name.capitalize()} correct."
        else:
            return 0, f"{field_name.capitalize()} incorrect (Expected: {expected}, Got: {actual})."

    # 2. Name Exact Match (15 pts)
    pts, msg = check_field('title', exp_title, 15)
    score += pts
    feedback.append(msg)

    # 3. Address (15 pts) - Allow partial match (e.g. if they added "St" or "Ave" by mistake, but main part is there)
    # Using strict match per requirements, but verifier logic can be slightly lenient on case/spacing
    pts, msg = check_field('address', exp_address, 15)
    score += pts
    feedback.append(msg)

    # 4. City (10 pts)
    pts, msg = check_field('city', exp_city, 10)
    score += pts
    feedback.append(msg)

    # 5. State (5 pts)
    pts, msg = check_field('state', exp_state, 5)
    score += pts
    feedback.append(msg)

    # 6. Zip (5 pts)
    pts, msg = check_field('zipcode', exp_zip, 5)
    score += pts
    feedback.append(msg)

    # 7. Phone (10 pts) - Strip non-digits for comparison
    actual_phone_digits = "".join(filter(str.isdigit, str(school.get('phone', ''))))
    exp_phone_digits = "".join(filter(str.isdigit, exp_phone))
    
    if exp_phone_digits in actual_phone_digits and len(actual_phone_digits) >= 10:
        score += 10
        feedback.append("Phone correct.")
    else:
        feedback.append(f"Phone incorrect (Expected digits: {exp_phone_digits}, Got: {actual_phone_digits}).")

    # 8. Anti-gaming: New Record (15 pts)
    if result.get('is_new_record', False):
        score += 15
        feedback.append("Verified new record creation.")
    else:
        feedback.append("Warning: Record ID existed before task started (Anti-gaming check failed).")

    # Determine Pass/Fail
    # Threshold: 60 points
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }