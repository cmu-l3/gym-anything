#!/usr/bin/env python3
"""
Verifier for edit_employee_host task.

Criteria:
1. Database file modified during task (anti-gaming).
2. New values found in database strings (persistence check).
3. VLM verifies the final UI state shows the correct values.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_employee_host(traj, env_info, task_info):
    """
    Verify the employee record was edited correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Persistence Check (40 points)
    db_modified = result.get('db_modified', False)
    new_values_count = result.get('new_values_count', 0)
    
    if db_modified:
        score += 10
        feedback_parts.append("Database file modified")
    else:
        feedback_parts.append("Database NOT modified (changes not saved?)")
        
    # We expect 3 new values: Dept, Phone, Email
    if new_values_count == 3:
        score += 30
        feedback_parts.append("All 3 new values found in database")
    elif new_values_count > 0:
        score += (new_values_count * 10)
        feedback_parts.append(f"{new_values_count}/3 new values found in database")
    else:
        feedback_parts.append("No new values found in database")

    # 2. VLM Verification (60 points)
    # Check if the final screenshot shows the updated record
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        prompt = """
        Review this screenshot of the Jolly Lobby Track application.
        I am looking for an employee/host record for 'Sarah Mitchell'.
        
        Check for these specific updated details:
        1. Department: 'Product Development'
        2. Phone: '555-867-5309'
        3. Email: 's.mitchell@proddev.example.com' or similar
        
        Answer in JSON:
        {
            "record_visible": true/false,
            "department_matches": true/false,
            "phone_matches": true/false,
            "email_matches": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        try:
            vlm_response = query_vlm(image=final_screenshot, prompt=prompt)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('record_visible'):
                vlm_score += 10
                feedback_parts.append("Record visible in screenshot")
                
                if parsed.get('department_matches'):
                    vlm_score += 15
                    feedback_parts.append("Department verified visually")
                if parsed.get('phone_matches'):
                    vlm_score += 15
                    feedback_parts.append("Phone verified visually")
                if parsed.get('email_matches'):
                    vlm_score += 20
                    feedback_parts.append("Email verified visually")
            else:
                feedback_parts.append("Record not visible in final screenshot")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM verification failed")
    
    score += vlm_score

    # Pass logic: Need mostly correct DB update OR perfect visual proof
    # Threshold: 60
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }