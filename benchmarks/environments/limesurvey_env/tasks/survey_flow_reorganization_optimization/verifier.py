#!/usr/bin/env python3
"""
Verifier for Survey Flow Reorganization and Optimization task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_survey_flow_reorganization(traj, env_info, task_info):
    """
    Verify that the agent Reordered the survey groups correctly and updated question attributes.
    
    Expected State:
    1. Group Order: Informed Consent < Shopping Habits < Demographics
    2. Question 'CONSENT1': Mandatory = 'Y'
    3. Question 'DEMO_INC': Mandatory = 'N'
    """
    
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

    score = 0
    feedback_parts = []
    
    # Extract Data
    orders = result.get("group_orders", {})
    order_consent = orders.get("consent", 999)
    order_shopping = orders.get("shopping", 999)
    order_demo = orders.get("demographics", 999)
    
    q_attrs = result.get("questions", {})
    mand_consent = q_attrs.get("consent_mandatory", "N")
    mand_income = q_attrs.get("income_mandatory", "Y")

    # CRITERION 1: Group Order (60 pts total)
    # Logic: Consent < Shopping < Demo
    
    # Check absolute positions if indices are clean (0,1,2), or relative if sparse
    # The crucial part is the relative order.
    
    order_correct = True
    
    if order_consent < order_shopping:
        score += 20
        feedback_parts.append("Consent group placed before Shopping.")
    else:
        order_correct = False
        feedback_parts.append(f"Consent group order ({order_consent}) is not before Shopping ({order_shopping}).")

    if order_shopping < order_demo:
        score += 20
        feedback_parts.append("Shopping group placed before Demographics.")
    else:
        order_correct = False
        feedback_parts.append(f"Shopping group order ({order_shopping}) is not before Demographics ({order_demo}).")

    # Bonus for Consent being absolute first (usually 0)
    if order_consent == 0:
        score += 10
        feedback_parts.append("Consent group is correctly first.")
    
    # Bonus for Demo being absolute last (usually index 2 in a 3 group survey)
    # We check if it's > shopping and consent
    if order_demo > order_shopping and order_demo > order_consent:
        score += 10
        feedback_parts.append("Demographics group is correctly last.")

    # CRITERION 2: Consent Mandatory (20 pts)
    if mand_consent == "Y":
        score += 20
        feedback_parts.append("Consent question correctly set to Mandatory.")
    else:
        feedback_parts.append(f"Consent question mandatory status is '{mand_consent}' (Expected 'Y').")

    # CRITERION 3: Income Optional (20 pts)
    if mand_income == "N":
        score += 20
        feedback_parts.append("Income question correctly set to Optional.")
    else:
        feedback_parts.append(f"Income question mandatory status is '{mand_income}' (Expected 'N').")

    # Pass Threshold
    # Must get the ordering mostly right and at least one setting
    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }