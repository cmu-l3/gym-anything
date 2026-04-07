#!/usr/bin/env python3
"""
Verifier for Update Student Demographics task.
Verifies that specific fields were updated while others remain unchanged.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_student_demographics(traj, env_info, task_info):
    """
    Verify student demographic updates.
    
    Scoring Strategy (100 pts total):
    - Address Updated: 15 pts
    - City Updated: 10 pts
    - State Updated: 5 pts
    - Zipcode Updated: 10 pts
    - Phone Updated: 20 pts
    - Email Updated: 20 pts
    - Name Intact: 10 pts (Anti-corruption check)
    - DOB Intact: 10 pts (Anti-corruption check)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic Checks
    if not result.get("student_found", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The student record 'Maria Elena Rodriguez' (ID 100) was deleted or could not be found in the database."
        }

    actual = result.get("student_data", {})
    expected = task_info.get("metadata", {}).get("expected_values", {})
    integrity = task_info.get("metadata", {}).get("integrity_check", {})

    score = 0
    feedback = []
    
    # 3. Verify Updates (80 pts)
    
    # Helper for case-insensitive strip comparison
    def check_field(field_name, actual_val, expected_val, points):
        # Normalize strings
        a = str(actual_val).strip().lower() if actual_val else ""
        e = str(expected_val).strip().lower() if expected_val else ""
        
        # Phone specific normalization (remove dashes/spaces/parens)
        if field_name == "phone":
            a = ''.join(filter(str.isdigit, a))
            e = ''.join(filter(str.isdigit, e))

        if a == e:
            return points, f"{field_name.capitalize()} correct."
        else:
            return 0, f"{field_name.capitalize()} incorrect (Expected '{expected_val}', got '{actual_val}')."

    # Check Address
    p, msg = check_field("address", actual.get("address"), expected.get("address"), 15)
    score += p
    feedback.append(msg)

    # Check City
    p, msg = check_field("city", actual.get("city"), expected.get("city"), 10)
    score += p
    feedback.append(msg)

    # Check State
    p, msg = check_field("state", actual.get("state"), expected.get("state"), 5)
    score += p
    feedback.append(msg)

    # Check Zip
    p, msg = check_field("zipcode", actual.get("zipcode"), expected.get("zipcode"), 10)
    score += p
    feedback.append(msg)

    # Check Phone
    p, msg = check_field("phone", actual.get("phone"), expected.get("phone"), 20)
    score += p
    feedback.append(msg)

    # Check Email
    p, msg = check_field("email", actual.get("email"), expected.get("email"), 20)
    score += p
    feedback.append(msg)

    # 4. Verify Integrity (20 pts)
    # Ensure the agent didn't accidentally change the name or DOB
    
    # Name Check
    name_correct = (
        str(actual.get("first_name")).lower() == str(integrity.get("first_name")).lower() and
        str(actual.get("last_name")).lower() == str(integrity.get("last_name")).lower()
    )
    if name_correct:
        score += 10
        feedback.append("Name integrity check passed.")
    else:
        feedback.append("PENALTY: Student name was altered.")

    # DOB Check
    dob_correct = str(actual.get("date_of_birth")) == str(integrity.get("date_of_birth"))
    if dob_correct:
        score += 10
        feedback.append("DOB integrity check passed.")
    else:
        feedback.append("PENALTY: Date of Birth was altered.")

    # 5. Final Evaluation
    # Pass threshold: 70 points. This requires most contact info to be correct 
    # and NO corruption of identity fields.
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }