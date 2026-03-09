#!/usr/bin/env python3
"""
Verifier for create_appointment_status task.

Criteria:
1. Database Record Exists (40 pts): Status 'V' must exist in appointment_status table.
2. Correct Description (30 pts): Description must match 'Vitals Done' (case-insensitive).
3. Correct Color (20 pts): Color must be a shade of green.
4. Admin Navigation (10 pts): VLM check to ensure agent accessed Administration.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_color_green(color_str):
    """
    Check if a color string represents a green color.
    Accepts hex codes (e.g., #00FF00, #32CD32) or simple names if Oscar stores them.
    """
    if not color_str:
        return False
    
    color_str = color_str.lower().strip()
    
    # Check for named colors
    if "green" in color_str or "lime" in color_str:
        return True
        
    # Check for Hex codes
    hex_match = re.search(r'#?([0-9a-f]{6})', color_str)
    if hex_match:
        hex_val = hex_match.group(1)
        r = int(hex_val[0:2], 16)
        g = int(hex_val[2:4], 16)
        b = int(hex_val[4:6], 16)
        
        # Simple heuristic: Green component should be dominant or significant
        # Strictly dominant: G > R and G > B
        if g > r and g > b:
            return True
        # Or significantly high green with low red (some teals/cyans might pass, which is acceptable)
        if g > 100 and r < 100:
            return True
            
    return False

def verify_create_appointment_status(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # 1. Load result data from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # --- Check 1: Record Exists (40 pts) ---
    record_found = result.get('record_found', False)
    record = result.get('record', {})
    
    if record_found and record.get('status') == 'V':
        score += 40
        feedback_parts.append("Status 'V' created successfully.")
    else:
        feedback_parts.append("Status 'V' NOT found in database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # --- Check 2: Correct Description (30 pts) ---
    desc = record.get('description', '')
    expected_desc = task_info.get('metadata', {}).get('expected_description', 'Vitals Done')
    
    if expected_desc.lower() in desc.lower():
        score += 30
        feedback_parts.append(f"Description '{desc}' is correct.")
    else:
        feedback_parts.append(f"Description '{desc}' mismatch (expected '{expected_desc}').")
        
    # --- Check 3: Correct Color (20 pts) ---
    color = record.get('color', '')
    if is_color_green(color):
        score += 20
        feedback_parts.append(f"Color '{color}' is valid (Green).")
    else:
        feedback_parts.append(f"Color '{color}' does not appear to be Green.")
        
    # --- Check 4: VLM Navigation Verification (10 pts) ---
    # We want to confirm the agent actually used the Admin interface
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's actions in Oscar EMR. 
    The goal was to go to the Administration panel and create an Appointment Status.
    
    Look at these screenshots. Do you see:
    1. The Oscar EMR "Administration" or "Admin" view?
    2. A form or list related to "Appointment Status" or "Schedule Settings"?
    
    Reply with JSON: {"admin_visited": true/false, "status_settings_seen": true/false}
    """
    
    try:
        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        parsed = vlm_result.get('parsed', {}) if vlm_result.get('success') else {}
        
        if parsed.get('admin_visited') or parsed.get('status_settings_seen'):
            score += 10
            feedback_parts.append("VLM verified Admin navigation.")
        else:
            feedback_parts.append("VLM did not clearly see Admin navigation.")
            # Fallback: if database record is perfect, we give benefit of doubt for UI lag
            if score >= 90:
                score += 10
                feedback_parts.append("(Auto-awarded nav points due to perfect output).")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # If VLM fails but task is done, don't penalize too hard
        if score >= 90:
            score += 10
            
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }