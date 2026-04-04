#!/usr/bin/env python3
"""
Verifier for record_investment_purchase task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_investment_purchase(traj, env_info, task_info):
    """
    Verify investment purchase recording.
    
    Criteria:
    1. Programmatic: Investments module enabled (20 pts)
    2. Programmatic: Investment item 'Northwind Strategic Fund' created (20 pts)
    3. Programmatic: Payment of 4,500.00 recorded on correct date (20 pts)
    4. VLM: Trajectory verification of Settings/Customize workflow (20 pts)
    5. VLM: Trajectory verification of Payment form filling (Investments account selected) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    feedback_parts = []
    
    # 1. Programmatic Verification
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
            
    if result.get('investments_enabled'):
        score += 20
        feedback_parts.append("Investments module enabled")
    else:
        feedback_parts.append("Investments module NOT enabled")
        
    if result.get('investment_item_found'):
        score += 20
        feedback_parts.append("Investment item created")
    else:
        feedback_parts.append("Investment item NOT found")
        
    if result.get('payment_found'):
        score += 20
        feedback_parts.append("Payment recorded")
    else:
        feedback_parts.append("Payment NOT found")

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=6)
    
    # Check 1: Did agent go to Settings/Customize?
    settings_prompt = """
    Review these screenshots of a user using Manager.io accounting software.
    Did the user navigate to the 'Settings' tab or click a 'Customize' button to enable new modules?
    Look for a screen showing checkboxes for different modules (like Bank Accounts, Investments, etc.).
    Return JSON: {"visited_settings": boolean}
    """
    settings_check = query_vlm(prompt=settings_prompt, images=frames)
    
    if settings_check.get('success') and settings_check.get('parsed', {}).get('visited_settings'):
        score += 20
        feedback_parts.append("Settings/Customize workflow verified")
    else:
        feedback_parts.append("No visual confirmation of Settings/Customize usage")

    # Check 2: Did agent select Investment account in payment?
    payment_prompt = """
    Review these screenshots. Did the user fill out a Payment or Purchase form?
    Specifically, look for the 'Account' column in the line items.
    Did they select 'Investments' and/or 'Northwind Strategic Fund' as the account?
    Return JSON: {"investment_account_selected": boolean}
    """
    payment_check = query_vlm(prompt=payment_prompt, images=frames)
    
    if payment_check.get('success') and payment_check.get('parsed', {}).get('investment_account_selected'):
        score += 20
        feedback_parts.append("Investment account selection verified")
    else:
        feedback_parts.append("Visual verification of payment allocation unclear")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }