#!/usr/bin/env python3
"""
Verifier for update_institution_config task.

Checks if the hospital institution details were correctly updated in the database.
Uses the JSON export from the container which contains search results for the target strings.
"""

import sys
import os
import json
import logging
import tempfile
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_institution_config(traj, env_info, task_info):
    """
    Verify that institution details were updated.
    
    Scoring:
    - Institution Name updated: 25 pts
    - Address updated: 25 pts
    - Phone updated: 15 pts
    - Fax updated: 15 pts
    - App left running: 10 pts
    - VLM Verification (visual check of admin screen): 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    # Note: Export script searches for these partial strings, so we check if the search found anything
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load result from container
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
            
    # 2. Check Database Findings
    
    # Name (25 pts)
    found_name = result.get('found_name_ocadmin') or result.get('found_name_openclinic')
    if found_name:
        score += 25
        feedback_parts.append("Institution Name updated successfully")
    else:
        feedback_parts.append("Institution Name NOT found in database")
        
    # Address (25 pts)
    found_address = result.get('found_address_ocadmin') or result.get('found_address_openclinic')
    if found_address:
        score += 25
        feedback_parts.append("Address updated successfully")
    else:
        feedback_parts.append("Address NOT found in database")
        
    # Phone (15 pts)
    found_phone = result.get('found_phone')
    if found_phone:
        score += 15
        feedback_parts.append("Phone updated successfully")
    else:
        feedback_parts.append("Phone NOT found in database")
        
    # Fax (15 pts)
    found_fax = result.get('found_fax')
    if found_fax:
        score += 15
        feedback_parts.append("Fax updated successfully")
    else:
        feedback_parts.append("Fax NOT found in database")
        
    # App State (10 pts)
    if result.get('app_running', False):
        score += 10
    else:
        feedback_parts.append("Application was closed")

    # 3. VLM Verification (10 pts)
    # Check if final screen shows configuration area or if we can see the values
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = """
        You are verifying a task where an agent was supposed to update hospital details.
        Look at this screenshot of the OpenClinic system.
        
        1. Does this look like an Administrative, Configuration, or System Management screen?
        2. Can you see any of these values: "Saint Helena", "450 Commonwealth", "804-555-0142"?
        
        Answer with JSON: {"is_admin_screen": bool, "values_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('is_admin_screen'):
                vlm_score += 5
            if parsed.get('values_visible'):
                vlm_score += 5
            
            score += vlm_score
            if vlm_score > 0:
                feedback_parts.append(f"Visual verification passed ({vlm_score}/10)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Grant minimal points if DB checks passed but VLM failed technically
            if score >= 50: 
                score += 5 

    passed = score >= 60 and bool(found_name)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }