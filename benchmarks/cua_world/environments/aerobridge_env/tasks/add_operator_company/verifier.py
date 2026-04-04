#!/usr/bin/env python3
"""
Verifier for add_operator_company task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_operator_company(traj, env_info, task_info):
    """
    Verify that the company 'Vayupath Aerial Technologies' was added correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    # Expected values
    metadata = task_info.get('metadata', {})
    exp_name = metadata.get('expected_full_name', "Vayupath Aerial Technologies")
    exp_email = metadata.get('expected_email', "ops@vayupath.in")
    exp_web = metadata.get('expected_website', "https://www.vayupath.in")
    exp_country = metadata.get('expected_country', "IN")

    score = 0
    feedback = []
    
    # 1. Check if record exists (Critical)
    if not result.get("record_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Company record 'Vayupath' not found in database."
        }
    
    score += 25
    feedback.append("Record created.")
    
    details = result.get("record_details", {})
    
    # 2. Name Check (15 pts)
    act_name = details.get("full_name", "")
    if act_name.strip() == exp_name:
        score += 15
        feedback.append(f"Full name correct ({act_name}).")
    else:
        feedback.append(f"Full name mismatch: Expected '{exp_name}', got '{act_name}'.")

    # 3. Email Check (15 pts)
    act_email = details.get("email", "")
    if act_email.strip() == exp_email:
        score += 15
        feedback.append(f"Email correct ({act_email}).")
    else:
        feedback.append(f"Email mismatch: Expected '{exp_email}', got '{act_email}'.")

    # 4. Website Check (10 pts)
    act_web = details.get("website", "")
    if exp_web in act_web:
        score += 10
        feedback.append("Website correct.")
    else:
        feedback.append(f"Website mismatch: Expected '{exp_web}', got '{act_web}'.")

    # 5. Country Check (5 pts)
    # Country often stored as 'IN' or 'India' or object string
    act_country = details.get("country", "")
    if "IN" in act_country or "India" in act_country:
        score += 5
        feedback.append("Country correct.")
    else:
        feedback.append(f"Country mismatch: Expected '{exp_country}', got '{act_country}'.")

    # 6. Anti-gaming: Count Check (10 pts)
    initial = result.get("initial_count", 0)
    final = result.get("final_count", 0)
    if final > initial:
        score += 10
        feedback.append("Company count increased.")
    else:
        feedback.append("Warning: Company count did not increase (record might have been overwritten?).")

    # 7. Common Name Check (10 pts)
    act_common = details.get("common_name", "")
    if "Vayupath" in act_common:
        score += 10
        feedback.append("Common name correct.")
    else:
        feedback.append(f"Common name mismatch.")
        
    # 8. Phone Check (10 pts)
    act_phone = details.get("phone_number", "")
    if "+91" in act_phone and "4567" in act_phone:
        score += 10
        feedback.append("Phone number correct.")
    else:
        feedback.append(f"Phone number mismatch.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }