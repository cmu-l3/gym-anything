#!/usr/bin/env python3
"""
Verifier for add_visit_purpose_category task.

Verification Strategy:
1. File Persistence (High Confidence): Checks if "Facility Maintenance" string exists in the application database file.
2. Agent Evidence (Medium Confidence): Checks if agent saved the required confirmation screenshot.
3. VLM Verification (High Confidence): Visual analysis of the confirmation screenshot or final state to confirm the UI shows the new category.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_visit_purpose(traj, env_info, task_info):
    """
    Verify that the 'Facility Maintenance' visit purpose was added.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_purpose_name', 'Facility Maintenance')
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Verification (40 points)
    # The export script greps the binary MDB file for the string
    db_string_found = result.get('string_found_in_db', False)
    initial_db_state = result.get('initial_db_state', 'unknown')
    
    if db_string_found:
        if initial_db_state == 'clean':
            score += 40
            feedback_parts.append("Database verification passed (new record found).")
        elif initial_db_state == 'exists':
            score += 20
            feedback_parts.append("Database check: Record exists, but it existed before task start (partial credit).")
        else:
            score += 30
            feedback_parts.append("Database check: Record found (baseline unknown).")
    else:
        feedback_parts.append("Database verification failed: 'Facility Maintenance' not found in database file.")

    # 2. Agent Evidence Check (10 points)
    # Did the agent verify its own work by saving a screenshot?
    confirmation_valid = result.get('confirmation_screenshot_valid', False)
    confirmation_path = result.get('confirmation_path', '')
    
    image_to_analyze = None
    
    if confirmation_valid:
        score += 10
        feedback_parts.append("Confirmation screenshot saved.")
        
        # Try to retrieve the confirmation screenshot for VLM
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(confirmation_path, temp_img.name)
            image_to_analyze = temp_img.name
        except Exception as e:
            logger.warning(f"Could not copy confirmation screenshot: {e}")
    else:
        feedback_parts.append("No valid confirmation screenshot saved.")

    # 3. VLM Verification (50 points)
    # Analyze either the agent's screenshot (preferred) or the final state screenshot
    
    # If we couldn't get the agent's screenshot, use the final frame from trajectory
    if not image_to_analyze:
        image_to_analyze = get_final_screenshot(traj)
    
    if image_to_analyze:
        prompt = (
            f"Look at this screenshot of the Lobby Track software. "
            f"I am looking for a visit purpose or reason named '{target_name}'. "
            f"1. Can you see the text '{target_name}' in a list, dropdown, or table? "
            f"2. Does the context look like a settings menu or a visitor registration form? "
            f"Return JSON with keys: 'text_visible' (bool), 'context_correct' (bool), 'confidence' (float 0-1)."
        )
        
        vlm_response = query_vlm(prompt=prompt, image=image_to_analyze)
        
        if vlm_response.get('success'):
            parsed = vlm_response.get('parsed', {})
            text_visible = parsed.get('text_visible', False)
            context_correct = parsed.get('context_correct', False)
            
            if text_visible:
                score += 30
                feedback_parts.append(f"VLM verified '{target_name}' is visible in UI.")
                if context_correct:
                    score += 20
                    feedback_parts.append("VLM verified correct UI context.")
                else:
                    score += 10
                    feedback_parts.append("VLM unsure about UI context.")
            else:
                feedback_parts.append(f"VLM could not find '{target_name}' in the screenshot.")
        else:
            feedback_parts.append("VLM analysis failed.")
            
        # Cleanup temp image if it was a file we created
        if isinstance(image_to_analyze, str) and os.path.exists(image_to_analyze) and "tmp" in image_to_analyze:
            try:
                os.unlink(image_to_analyze)
            except:
                pass

    # Final scoring logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }