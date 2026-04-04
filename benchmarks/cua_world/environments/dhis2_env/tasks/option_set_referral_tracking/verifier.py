#!/usr/bin/env python3
"""
Verifier for option_set_referral_tracking task.

Scoring (100 points total):
- Option Set 'Referral Reason' exists (MANDATORY): 25 pts
- Option Set Code matches 'REFERRAL_REASON': 5 pts
- Option Set contains >= 4 options: 15 pts
- Option Set contains all 6 specified options: 10 pts
- Options have correct codes: 10 pts
- Data Element 'Facility Referral Reason' exists: 20 pts
- Data Element linked to Option Set: 10 pts
- Data Element code matches 'FAC_REF_REASON': 5 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_option_set_referral_tracking(traj, env_info, task_info):
    """Verify creation of Option Set and Data Element."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Load Result JSON
    temp_path = ""
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/option_set_task_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse verification data: {e}"}
    finally:
        if temp_path and os.path.exists(temp_path):
            os.unlink(temp_path)

    # 2. Extract Data
    os_data = result.get('option_set', {})
    de_data = result.get('data_element', {})
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Check Option Set (Base 25 pts)
    # ---------------------------------------------------------
    if not os_data.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Option Set 'Referral Reason' was not found. Creation of the Option Set is mandatory."
        }
    
    score += 25
    feedback_parts.append("Option Set created (+25)")
    
    # Check Code (5 pts)
    if os_data.get('code') == 'REFERRAL_REASON':
        score += 5
        feedback_parts.append("Option Set code correct (+5)")
    else:
        feedback_parts.append(f"Option Set code mismatch (Found: {os_data.get('code')})")

    # Check Options (Count & Content) (25 pts total)
    options = os_data.get('options', [])
    opt_count = len(options)
    
    if opt_count >= 4:
        score += 15
        feedback_parts.append(f"Option Set has {opt_count} options (>=4) (+15)")
    else:
        feedback_parts.append(f"Option Set has only {opt_count} options (Need >=4)")

    # Verify specific options
    expected_options = {
        "EMOC": "Emergency obstetric care",
        "SURG": "Surgical intervention",
        "DIAG": "Diagnostic imaging",
        "SPEC": "Specialist consultation",
        "BTRANS": "Blood transfusion",
        "OTHER": "Other"
    }
    
    found_codes = {opt.get('code'): opt.get('displayName') for opt in options}
    
    # Check for all 6 options existence (by code or name)
    # We'll be lenient and check if we can match at least 6 distinct expected items
    matched_count = 0
    code_match_count = 0
    
    for exp_code, exp_name in expected_options.items():
        # Check by code
        if exp_code in found_codes:
            matched_count += 1
            code_match_count += 1
            continue
        
        # Check by name (loose match)
        name_match = False
        for opt in options:
            if exp_name.lower() in opt.get('displayName', '').lower():
                matched_count += 1
                name_match = True
                break
    
    if matched_count >= 6:
        score += 10
        feedback_parts.append("All 6 options present (+10)")
    
    if code_match_count >= 4:
        score += 10
        feedback_parts.append("Option codes correct (+10)")

    # ---------------------------------------------------------
    # Check Data Element (Base 20 pts)
    # ---------------------------------------------------------
    if de_data.get('found'):
        score += 20
        feedback_parts.append("Data Element created (+20)")
        
        # Linkage Check (10 pts)
        linked_os_id = de_data.get('linked_option_set_id')
        actual_os_id = os_data.get('id')
        
        if linked_os_id and linked_os_id == actual_os_id:
            score += 10
            feedback_parts.append("Data Element correctly linked to Option Set (+10)")
        else:
            feedback_parts.append("Data Element NOT linked to correct Option Set")
            
        # Code Check (5 pts)
        if de_data.get('code') == 'FAC_REF_REASON':
            score += 5
            feedback_parts.append("Data Element code correct (+5)")
    else:
        feedback_parts.append("Data Element 'Facility Referral Reason' not found")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }