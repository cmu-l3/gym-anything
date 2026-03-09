#!/usr/bin/env python3
"""
Verifier for Survey Data Cleaning Task
"""

import json
import os
import tempfile

def verify_survey_data_cleaning_pruning(traj, env_info, task_info):
    """
    Verifies that the agent cleaned the survey data correctly.
    
    Criteria:
    1. Zero records with submitdate IS NULL (25 pts)
    2. Zero records with Name='TEST' (25 pts)
    3. Zero records with Email='*@example.com' (25 pts)
    4. All valid records (Jane Doe, Marcus Smith, Li Wei) preserved (25 pts)
    
    Penalty:
    - If survey was deactivated (table missing), 0 points.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    # Gate: Survey must be active (table exists)
    if not result.get("survey_active", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The survey response table was not found. Did you deactivate the survey? Deactivating truncates the response table."
        }

    score = 0
    feedback = []

    # 1. Check Bad Data (Goal: 0)
    bad_counts = result.get("bad_data_counts", {})
    
    # Incomplete
    incomplete = bad_counts.get("incomplete", -1)
    if incomplete == 0:
        score += 25
        feedback.append("Successfully removed all incomplete responses.")
    else:
        feedback.append(f"Failed: {incomplete} incomplete responses remain.")

    # Test Name
    test_name = bad_counts.get("test_name", -1)
    if test_name == 0:
        score += 25
        feedback.append("Successfully removed 'TEST' responses.")
    else:
        feedback.append(f"Failed: {test_name} record(s) with name 'TEST' remain.")

    # Spam Email
    spam_email = bad_counts.get("spam_email", -1)
    if spam_email == 0:
        score += 25
        feedback.append("Successfully removed '@example.com' spam responses.")
    else:
        feedback.append(f"Failed: {spam_email} record(s) with '@example.com' remain.")

    # 2. Check Good Data (Goal: Preserved)
    good_data = result.get("good_data_preserved", {})
    jane = good_data.get("Jane_Doe", 0)
    marcus = good_data.get("Marcus_Smith", 0)
    li = good_data.get("Li_Wei", 0)

    if jane >= 1 and marcus >= 1 and li >= 1:
        score += 25
        feedback.append("All valid records preserved.")
    else:
        missing = []
        if jane < 1: missing.append("Jane Doe")
        if marcus < 1: missing.append("Marcus Smith")
        if li < 1: missing.append("Li Wei")
        feedback.append(f"Failed: Valid records deleted/missing: {', '.join(missing)}")

    # Final tally
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }