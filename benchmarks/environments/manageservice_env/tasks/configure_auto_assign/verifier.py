#!/usr/bin/env python3
"""
Verifier for configure_auto_assign task.

Verification Strategy:
1. Primary: Database checks via exported JSON.
   - GlobalConfig['AUTO_ASSIGN_STATUS'] == 'true'
   - GlobalConfig['AUTO_ASSIGN_MODEL'] contains 'Round' or specific ID
   - TechAutoAssignExclude contains Administrator ID
2. Secondary: VLM verification of the final screenshot to confirm UI state.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_auto_assign(traj, env_info, task_info):
    """
    Verify that Technician Auto Assign is enabled, set to Round Robin, and excludes Administrator.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    db_check = result.get('db_check', {})
    
    # --------------------------------------------------------------------------
    # CRITERION 1: Feature Enabled (30 points)
    # --------------------------------------------------------------------------
    status_val = str(db_check.get('status', '')).lower()
    if status_val == 'true':
        score += 30
        feedback.append("Tech Auto Assign is ENABLED (Database confirmed).")
    else:
        feedback.append(f"Tech Auto Assign is NOT enabled (DB value: {status_val}).")

    # --------------------------------------------------------------------------
    # CRITERION 2: Round Robin Selected (30 points)
    # --------------------------------------------------------------------------
    # The DB value might be 'Round Robin', 'RoundRobin', or an ID. 
    # We check the model field and the dump for safety.
    model_val = str(db_check.get('model', '')).lower()
    all_params = str(db_check.get('all_params_dump', '')).lower()
    
    # "Round Robin" matches often appear in params or explicitly in model
    if 'round' in model_val or 'robin' in model_val or 'round' in all_params:
        score += 30
        feedback.append("Round Robin method selected (Database confirmed).")
    else:
        feedback.append(f"Round Robin method NOT detected (Model value: {model_val}).")

    # --------------------------------------------------------------------------
    # CRITERION 3: Administrator Excluded (30 points)
    # --------------------------------------------------------------------------
    is_excluded = db_check.get('is_admin_excluded', False)
    if is_excluded:
        score += 30
        feedback.append("Administrator is correctly excluded.")
    else:
        feedback.append("Administrator is NOT in the exclusion list.")

    # --------------------------------------------------------------------------
    # CRITERION 4: App Running (10 points)
    # --------------------------------------------------------------------------
    if result.get('app_running', False):
        score += 10
    else:
        feedback.append("Application was not running at verification time.")

    # --------------------------------------------------------------------------
    # VLM FALLBACK / CONFIRMATION
    # If score is borderline (e.g. DB mapping issues), VLM can save it.
    # --------------------------------------------------------------------------
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot and score < 90:
        logger.info("Triggering VLM verification due to incomplete score...")
        prompt = """
        Analyze this ServiceDesk Plus screenshot.
        I am looking for the 'Technician Auto Assign' settings.
        
        1. Is the status 'Enable' or 'On'?
        2. Is 'Round Robin' selected?
        3. Is 'Administrator' listed under 'Exceptions' or 'Excluded Technicians'?
        
        Return JSON: {"enabled": bool, "round_robin": bool, "admin_excluded": bool}
        """
        
        try:
            vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('enabled') and 'ENABLED' not in str(feedback):
                score += 30
                feedback.append("VLM confirmed feature is Enabled.")
                
            if parsed.get('round_robin') and 'Round Robin' not in str(feedback):
                score += 30
                feedback.append("VLM confirmed Round Robin is selected.")
                
            if parsed.get('admin_excluded') and 'excluded' not in str(feedback):
                score += 30
                feedback.append("VLM confirmed Administrator is excluded.")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold: Must have enabled feature, set round robin, and excluded admin
    # Basically needs 90 points.
    passed = score >= 90

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }