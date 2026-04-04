#!/usr/bin/env python3
"""
Verifier for personnel_data_input_masks task.

Checks for:
1. Active survey titled "Personnel Data Verification 2025"
2. Question "Emergency Mobile": Mask '(999) 999-9999', Hide tip=1
3. Question "Desk Location Code": Mask '99-99-999'
4. Question "Current Annual Salary": Min=20000, Prefix=$, Suffix=USD, Integer only (implicit in type usually or attribute)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_personnel_data_input_masks(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    db_data = result.get("db_data", {})
    
    # 1. Check Survey Existence and Status (10 pts)
    score = 0
    feedback_parts = []
    
    if not db_data.get("survey_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey 'Personnel Data Verification 2025' not found."
        }
    
    # Survey found
    score += 5
    feedback_parts.append("Survey found")

    if db_data.get("survey_active") == "Y":
        score += 5
        feedback_parts.append("Survey is active")
    else:
        feedback_parts.append("Survey is NOT active")

    questions = db_data.get("questions", [])
    
    # Identify questions by text content or key attributes to avoid rigid ID checks
    # Criteria:
    # Mobile: Text contains "Mobile" or "Phone" or check attributes
    # Location: Text contains "Location" or "Desk"
    # Salary: Text contains "Salary"
    
    q_mobile = None
    q_location = None
    q_salary = None

    for q in questions:
        text = q.get("text", "").lower()
        if "mobile" in text or "phone" in text:
            q_mobile = q
        elif "location" in text or "desk" in text:
            q_location = q
        elif "salary" in text or "annual" in text:
            q_salary = q

    # 2. Verify Emergency Mobile (35 pts)
    # Mask: (999) 999-9999 (25 pts)
    # Hide tip: 1 (10 pts)
    if q_mobile:
        attrs = q_mobile.get("attributes", {})
        mask = attrs.get("input_mask", "")
        hide_tip = str(attrs.get("hide_tip", "0"))
        
        # Check Mask
        if mask == "(999) 999-9999":
            score += 25
            feedback_parts.append("Mobile mask correct")
        else:
            feedback_parts.append(f"Mobile mask incorrect (Found: '{mask}')")
            
        # Check Hide Tip
        if hide_tip == "1":
            score += 10
            feedback_parts.append("Mobile tip hidden")
        else:
            feedback_parts.append("Mobile tip NOT hidden")
    else:
        feedback_parts.append("Mobile question not found")

    # 3. Verify Desk Location Code (20 pts)
    # Mask: 99-99-999
    if q_location:
        attrs = q_location.get("attributes", {})
        mask = attrs.get("input_mask", "")
        
        if mask == "99-99-999":
            score += 20
            feedback_parts.append("Location mask correct")
        else:
            feedback_parts.append(f"Location mask incorrect (Found: '{mask}')")
    else:
        feedback_parts.append("Location question not found")

    # 4. Verify Salary (35 pts)
    # Prefix: $ (10 pts)
    # Suffix: USD (10 pts)
    # Min Value: 20000 (15 pts)
    # Integer check is usually part of question type 'N' or attribute 'num_value_int_only' (not always exposed in same table depending on version, so we focus on explicit attributes requested)
    if q_salary:
        attrs = q_salary.get("attributes", {})
        prefix = attrs.get("prefix", "")
        suffix = attrs.get("suffix", "")
        min_val = str(attrs.get("min_num_value_n", ""))
        
        if prefix == "$":
            score += 10
            feedback_parts.append("Salary prefix correct")
        else:
            feedback_parts.append(f"Salary prefix incorrect (Found: '{prefix}')")

        if suffix == "USD":
            score += 10
            feedback_parts.append("Salary suffix correct")
        else:
            feedback_parts.append(f"Salary suffix incorrect (Found: '{suffix}')")

        # Handle float/int conversion for min value check
        try:
            if float(min_val) == 20000:
                score += 15
                feedback_parts.append("Salary min value correct")
            else:
                feedback_parts.append(f"Salary min value incorrect (Found: '{min_val}')")
        except ValueError:
            feedback_parts.append(f"Salary min value missing or invalid")
    else:
        feedback_parts.append("Salary question not found")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }