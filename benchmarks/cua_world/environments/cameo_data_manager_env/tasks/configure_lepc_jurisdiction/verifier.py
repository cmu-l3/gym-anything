#!/usr/bin/env python3
"""
Verifier for Configure LEPC Jurisdiction task.

Strategy:
1. Programmatic: Check if CAMEO data file was modified (indicates save action).
2. Programmatic: Check if application is still running.
3. VLM: Verify specific text fields in the final screenshot/trajectory.
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_lepc_jurisdiction(traj, env_info, task_info):
    """
    Verify LEPC configuration.
    
    Scoring:
    - App running: 10 pts
    - Data saved (file modified): 20 pts
    - VLM Verification of fields: 70 pts
      - Name: 20
      - Address/City/State: 20
      - Phone: 10
      - Contacts/Other: 20
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, paths might need care, but copy_from_env handles container paths
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 2. Check App State (10 pts)
    if result.get('app_running'):
        score += 10
        feedback.append("Application is running.")
    else:
        feedback.append("Application was closed.")
        
    # 3. Check File Modification (20 pts)
    # This proves the user actually hit 'Save' or modified the DB
    if result.get('file_modified'):
        score += 20
        feedback.append("Configuration changes saved to disk.")
    else:
        feedback.append("No changes detected on disk (did you save?).")

    # 4. VLM Verification (70 pts)
    # We use the final screenshot to check the entered values
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze this screenshot from CAMEO Data Manager.
    The user should have configured the LEPC (Local Emergency Planning Committee) Jurisdiction information.
    
    Check for the presence of these specific values:
    1. LEPC Name: "Cuyahoga County Local Emergency Planning Committee" (or similar)
    2. State: "OH" or "Ohio"
    3. Address: "323 Lakeside" or "Cleveland"
    4. Phone: "(216) 443-5700"
    5. Chairperson/Contact: "Emergency Management Director" or "Cuyahoga County Emergency Services"
    
    Return JSON:
    {
        "lepc_name_correct": boolean,
        "address_correct": boolean,
        "phone_correct": boolean,
        "other_details_correct": boolean,
        "screen_is_jurisdiction_setup": boolean
    }
    """
    
    vlm_res = query_vlm(prompt=vlm_prompt, image=final_img)
    
    if vlm_res and vlm_res.get('success'):
        parsed = vlm_res.get('parsed', {})
        
        # Check Name (20 pts)
        if parsed.get('lepc_name_correct'):
            score += 20
            feedback.append("LEPC Name verified.")
            
        # Check Address (20 pts)
        if parsed.get('address_correct'):
            score += 20
            feedback.append("Address/Location verified.")
            
        # Check Phone (10 pts)
        if parsed.get('phone_correct'):
            score += 10
            feedback.append("Phone number verified.")
            
        # Check Other (20 pts)
        if parsed.get('other_details_correct'):
            score += 20
            feedback.append("Additional details verified.")
            
        if not parsed.get('screen_is_jurisdiction_setup') and score < 50:
            feedback.append("Screenshot does not appear to show the Jurisdiction Setup screen.")
    else:
        feedback.append("Visual verification failed (VLM error).")
        
    # Final Pass Check
    # Must have saved to disk AND have reasonable visual confirmation (>60 total)
    passed = (score >= 60) and result.get('file_modified')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }