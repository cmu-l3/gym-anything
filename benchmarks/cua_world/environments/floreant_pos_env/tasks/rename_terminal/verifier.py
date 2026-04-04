#!/usr/bin/env python3
"""
Verifier for rename_terminal task.
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_terminal(traj, env_info, task_info):
    """
    Verifies that the POS terminal was renamed to 'Front Counter'.
    
    Criteria:
    1. Database reflects the new name 'Front Counter' (40 pts)
    2. Database files were modified during the task (20 pts)
    3. Terminal name is different from initial name (10 pts)
    4. App was running at the end (10 pts)
    5. VLM Visual verification of final state (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result JSON
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
    
    # Extract data
    final_name = result.get("final_terminal_name", "").strip()
    initial_name = result.get("initial_terminal_name", "").strip()
    db_modified = result.get("db_modified", False)
    app_running = result.get("app_was_running", False)
    target_name = task_info.get("metadata", {}).get("target_terminal_name", "Front Counter")
    
    # 1. Check Terminal Name (40 pts)
    if final_name == target_name:
        score += 40
        feedback_parts.append(f"Success: Terminal name matches '{target_name}'.")
    elif target_name.lower() in final_name.lower():
        score += 20
        feedback_parts.append(f"Partial: Terminal name '{final_name}' is close to '{target_name}'.")
    else:
        feedback_parts.append(f"Fail: Terminal name is '{final_name}', expected '{target_name}'.")
        
    # 2. Check Modification Timestamp (20 pts)
    if db_modified:
        score += 20
        feedback_parts.append("Database file modification detected.")
    else:
        feedback_parts.append("Warning: Database files were not modified.")
        
    # 3. Check Change Occurred (10 pts)
    if final_name != initial_name and final_name != "":
        score += 10
        feedback_parts.append("Terminal name was changed from initial value.")
    
    # 4. App Running (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("Application was running correctly.")
        
    # 5. VLM Verification (20 pts)
    # We use VLM to ensure the user didn't just hack the DB but used the UI
    # or to verify success if DB check is ambiguous.
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = f"""
        You are verifying a Point of Sale configuration task.
        Goal: Rename the terminal to '{target_name}'.
        
        Look at the screenshot. 
        1. Do you see a window titled 'Configuration' or 'Terminal'?
        2. Do you see a text field containing '{target_name}'?
        3. Do you see the main POS screen with title/header '{target_name}'?
        
        Answer JSON: {{ "ui_visible": boolean, "name_visible": boolean, "confidence": number }}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("name_visible", False):
                vlm_score = 20
                feedback_parts.append("VLM confirmed name visible on screen.")
            elif parsed.get("ui_visible", False):
                vlm_score = 10
                feedback_parts.append("VLM confirmed configuration UI visible.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            
    score += vlm_score
    
    passed = (score >= 70) and (final_name == target_name)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }