#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_referral_status(traj, env_info, task_info):
    """
    Verifies that the agent updated the referral order status in NOSH.
    
    Strategy:
    1. DB Check: Verify specific order_id status changed from 'pending' to 'completed'/'received'.
    2. VLM Check: Verify trajectory shows interaction with Orders page.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    final_status = result.get("final_order_status", "").lower()
    date_completed = result.get("date_completed_db", "NULL")
    acceptable_statuses = ["complete", "completed", "received", "closed", "done"]
    
    score = 0
    feedback_parts = []
    
    # 3. Database Verification (Primary)
    if final_status in acceptable_statuses:
        score += 50
        feedback_parts.append(f"✅ Order status successfully updated to '{final_status}'")
    elif final_status == "pending":
        feedback_parts.append("❌ Order status is still 'pending'")
    elif final_status == "not_found":
        feedback_parts.append("❌ Target order was deleted or not found")
    else:
        feedback_parts.append(f"⚠️ Order status changed to unexpected value: '{final_status}'")
        score += 10  # Small partial credit for changing it at all

    # Check date completed field (often auto-filled by NOSH on completion)
    if date_completed and date_completed != "NULL":
        score += 20
        feedback_parts.append("✅ Completion date recorded in database")

    # 4. VLM Trajectory Verification (Secondary)
    # We want to confirm the agent actually navigated there
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of an Electronic Health Record (EHR) interaction.
    The goal was to "Update the status of a Cardiology referral to Completed".
    
    Determine:
    1. Did the user navigate to a patient chart?
    2. Did the user view an 'Orders' or 'Referrals' list?
    3. Is there visual evidence of a status dropdown or 'Complete/Close' button being clicked?
    
    Answer yes/no for each and provide a brief reasoning.
    """
    
    vlm_score = 0
    try:
        if env_info.get('query_vlm'):
            vlm_response = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
            # Simple keyword heuristic on VLM response
            res_text = vlm_response.get('result', '').lower()
            if "yes" in res_text and ("order" in res_text or "referral" in res_text):
                vlm_score = 30
                feedback_parts.append("✅ Visual evidence of order management workflow")
            else:
                feedback_parts.append("⚠️ Visual evidence unclear on workflow")
        else:
            # Fallback if VLM unavailable but DB passed
            if score >= 50: 
                vlm_score = 30
                feedback_parts.append("✅ (VLM skipped, assuming success based on DB)")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        if score >= 50: vlm_score = 30 # Graceful degradation

    score += vlm_score

    # 5. Final Scoring
    # Pass threshold: Must have correct DB status (50pts) + partial VLM or date check
    passed = (score >= 70) and (final_status in acceptable_statuses)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }