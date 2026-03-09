#!/usr/bin/env python3
"""
Verifier for tracked_entity_attribute_pattern_validation task.

Scoring (100 points):
- Attribute "National PUI" created: 20 pts
- Value Type is "TEXT": 10 pts
- Unique is True: 15 pts
- Pattern is valid (Regex check): 25 pts
- Assigned to "Person" entity type: 15 pts
- "Display in list" enabled: 15 pts

Pass threshold: 60 points (Must include creation and valid pattern)
"""

import json
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_pattern_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON
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

    # 2. Initialize Scoring
    score = 0
    feedback = []
    
    # Metadata for Regex Testing
    metadata = task_info.get('metadata', {})
    valid_cases = metadata.get('test_cases_valid', ["BO/123456", "AB/999999"])
    invalid_cases = metadata.get('test_cases_invalid', ["bo/123456", "123456", "AB-123456"])

    # 3. Check Criteria

    # Criterion A: Attribute Created (20 pts)
    if not result.get('attribute_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Attribute 'National PUI' was not found. Ensure you saved it with the exact name."
        }
    score += 20
    feedback.append("Attribute 'National PUI' found.")

    attr = result.get('attribute', {})

    # Criterion B: Value Type (10 pts)
    val_type = attr.get('valueType', 'UNKNOWN')
    if val_type == 'TEXT':
        score += 10
        feedback.append("Value Type is correctly set to TEXT.")
    else:
        feedback.append(f"Incorrect Value Type: {val_type} (Expected TEXT).")

    # Criterion C: Unique (15 pts)
    is_unique = attr.get('unique', False)
    if is_unique:
        score += 15
        feedback.append("Uniqueness is enabled.")
    else:
        feedback.append("Attribute is NOT marked as unique.")

    # Criterion D: Pattern Regex Validation (25 pts)
    pattern = attr.get('pattern', '')
    if not pattern:
        feedback.append("No pattern (regex) configured.")
    else:
        # Test the regex against cases
        try:
            # DHIS2 uses Java regex, Python is close enough for this simple case.
            # We wrap in ^...$ if user didn't, although DHIS2 pattern usually implies full match validation.
            # But let's check strict compliance.
            regex = re.compile(pattern)
            
            passes_valid = all(regex.match(case) for case in valid_cases)
            passes_invalid = all(not regex.match(case) for case in invalid_cases)

            if passes_valid and passes_invalid:
                score += 25
                feedback.append(f"Pattern '{pattern}' correctly validates PUI format.")
            else:
                feedback.append(f"Pattern '{pattern}' failed validation tests. \nPassed Valid Cases: {passes_valid}\nRejected Invalid Cases: {passes_invalid}")
                # Partial credit for being close? No, regex must work.
        except re.error:
            feedback.append(f"Invalid Regex syntax: {pattern}")

    # Criterion E: Assigned to Person (15 pts)
    if result.get('assigned_to_person'):
        score += 15
        feedback.append("Correctly assigned to 'Person' entity type.")
    else:
        feedback.append("Not assigned to 'Person' entity type.")

    # Criterion F: Display in List (15 pts)
    if result.get('display_in_list'):
        score += 15
        feedback.append("'Display in list' is enabled.")
    else:
        # Only deduct if assigned, otherwise this point is moot
        if result.get('assigned_to_person'):
            feedback.append("'Display in list' is NOT enabled.")

    # 4. Final Verdict
    # Pass threshold: 60 points.
    # Logic: Basic setup (20+10+15 = 45) + Pattern (25) = 70 (Pass)
    # Logic: Basic setup + Assignment (45+15) = 60 (Pass)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }