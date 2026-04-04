#!/usr/bin/env python3
"""
Verifier for create_user_type task in Floreant POS.

Verification Criteria:
1. Database Integrity (Primary):
   - A record with name "Shift Supervisor" exists in USER_TYPE table.
   - Database files were modified during the task window.
2. Visual Verification (Secondary/VLM):
   - Trajectory analysis to confirm Back Office navigation.
   - Final screenshot showing the new user type in the list.

Scoring:
- 40 pts: Record found in database
- 20 pts: Database modified during task (anti-gaming)
- 40 pts: VLM visual confirmation of workflow
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_type(traj, env_info, task_info):
    """
    Verify that the 'Shift Supervisor' user type was created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Load Task Result JSON (Database Check)
    # ================================================================
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
            
    record_found = result.get("record_found", False)
    db_modified = result.get("db_modified_during_task", False)

    if record_found:
        score += 40
        feedback_parts.append("Success: 'Shift Supervisor' record found in database.")
    else:
        feedback_parts.append("Failure: 'Shift Supervisor' record NOT found in database.")

    if db_modified:
        score += 20
        feedback_parts.append("Database modification confirmed.")
    elif record_found:
        feedback_parts.append("Warning: Database timestamp did not update (unusual but possible if cached).")
    else:
        feedback_parts.append("No database modification detected.")

    # ================================================================
    # 2. VLM Verification (Visual Workflow)
    # ================================================================
    # We check if the agent actually navigated the back office menus
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        frames.append(final_shot)
        
    if frames:
        prompt = """
        You are verifying a task in Floreant POS where the user must create a new User Type called 'Shift Supervisor'.
        
        Review these screenshots from the agent's session. Look for:
        1. The 'Back Office' or 'Administration' interface (not just the main table map).
        2. A form or list related to 'User Types' or 'Roles'.
        3. The text 'Shift Supervisor' being typed or appearing in a list.
        
        Return JSON:
        {
            "back_office_accessed": true/false,
            "user_type_screen_seen": true/false,
            "shift_supervisor_text_seen": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            vlm_score = 0
            if parsed.get("back_office_accessed"): vlm_score += 10
            if parsed.get("user_type_screen_seen"): vlm_score += 10
            if parsed.get("shift_supervisor_text_seen"): vlm_score += 20
            
            score += vlm_score
            feedback_parts.append(f"Visual verification score: {vlm_score}/40")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("Visual verification skipped due to error.")
            # If DB check passed, we might still allow a pass, but score is lower
            if record_found:
                score += 20 # Grace points if technical VLM failure but DB success

    # ================================================================
    # 3. Final Evaluation
    # ================================================================
    # Pass threshold: Must have record in DB (primary) and reasonable total score
    passed = record_found and (score >= 55)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }