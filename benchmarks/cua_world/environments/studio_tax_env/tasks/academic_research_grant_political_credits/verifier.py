#!/usr/bin/env python3
"""Verifier for academic_research_grant_political_credits task."""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_academic_research_grant_political_credits(traj, env_info, task_info):
    """Verify Dr. Julian Vance's return."""
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/Desktop/academic_research_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # CRITERION 1: File Existence & Name (10 pts)
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    
    if file_exists and file_size > 500:
        score += 10
        feedback_parts.append("Return file 'julian_vance.24t' saved")
    else:
        feedback_parts.append("FAIL: Return file not found or too small")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Timestamp Valid (10 pts)
    if result.get('file_is_new', False):
        score += 10
        feedback_parts.append("File timestamp valid")
    else:
        feedback_parts.append("FAIL: File timestamp invalid")
        
    # CRITERION 3: Taxpayer Profile (10 pts)
    name_ok = result.get('contains_vance', False) and result.get('contains_julian', False)
    ns_ok = result.get('contains_ns', False)
    
    if name_ok and ns_ok:
        score += 10
        feedback_parts.append("Taxpayer profile (Julian Vance, NS) found")
    elif name_ok:
        score += 5
        feedback_parts.append("Taxpayer name found, NS missing")
    else:
        feedback_parts.append("FAIL: Taxpayer name not found")
        
    # CRITERION 4: T4 Employment Income (10 pts)
    if result.get('contains_115000', False):
        score += 10
        feedback_parts.append("T4 employment income $115,000 found")
    else:
        feedback_parts.append("FAIL: T4 employment income not found")
        
    # CRITERION 5: Net Research Grant (15 pts) - Core requirement
    has_net_grant = result.get('contains_6200', False)
    has_gross_grant = result.get('contains_28500', False)
    
    if has_net_grant:
        score += 15
        feedback_parts.append("Net research grant $6,200 found")
    elif has_gross_grant:
        feedback_parts.append("FAIL: Gross grant found but research expenses not properly deducted")
    else:
        feedback_parts.append("FAIL: Research grant not found")
        
    # CRITERION 6: Total Professional Dues (10 pts)
    if result.get('contains_2300', False):
        score += 10
        feedback_parts.append("Total professional dues $2,300 found")
    elif result.get('contains_1100', False) or result.get('contains_1200', False):
        score += 5
        feedback_parts.append("Partial professional dues found")
    else:
        feedback_parts.append("FAIL: Professional dues not found")
        
    # CRITERION 7: Federal Political Credit (7 pts)
    if result.get('contains_500', False):
        score += 7
        feedback_parts.append("Federal political contribution $500 found")
    else:
        feedback_parts.append("FAIL: Federal political contribution not found")
        
    # CRITERION 8: Provincial Political Credit (8 pts)
    if result.get('contains_300', False):
        score += 8
        feedback_parts.append("Provincial political contribution $300 found")
    else:
        feedback_parts.append("FAIL: Provincial political contribution not found")
        
    # CRITERION 9: VLM Verification (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            if images:
                prompt = """You are evaluating an agent's trajectory for a tax preparation task.
Did the agent actively use StudioTax 2024 to enter information?
Look for evidence of navigating forms, entering values, or saving the file.
Answer in JSON format: {"used_studiotax": true/false}"""
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_studiotax', False):
                        score += 20
                        feedback_parts.append("VLM confirmed StudioTax usage (+20 pts)")
                    else:
                        feedback_parts.append("VLM did not detect StudioTax usage")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            
    # Anti-gaming Constraint: The Net Research Grant correctly calculated is a core task requirement.
    if not has_net_grant:
        score = min(score, 55)
        
    passed = score >= 60 and has_net_grant
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }