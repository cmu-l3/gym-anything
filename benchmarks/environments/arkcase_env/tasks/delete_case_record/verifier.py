#!/usr/bin/env python3
"""
Verifier for delete_case_record task.

Criteria:
1. Target case "TEST-CASE-REMOVE-ME" must be deleted (API returns 404).
2. Control case "IMPORTANT-active-case-001" must still exist (API returns 200).
3. VLM verification should confirm the delete action was performed in the UI.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_case_record(traj, env_info, task_info):
    """
    Verify that the agent deleted the specific case and nothing else.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load API verification results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check API Results
    target_gone = result.get('target_case_gone', False)
    control_exists = result.get('control_case_exists', True)
    
    # Criterion 1: Target Deleted (60 pts)
    if target_gone:
        score += 60
        feedback_parts.append("✅ Target case successfully deleted")
    else:
        feedback_parts.append("❌ Target case still exists in database")

    # Criterion 2: Control Case Safe (20 pts)
    if control_exists:
        score += 20
        feedback_parts.append("✅ Control case preserved")
    else:
        feedback_parts.append("❌ WRONG CASE DELETED: Control case is missing!")

    # 3. VLM Verification (20 pts)
    # We look for the "Delete" dialog or confirmation in the trajectory
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
    
    vlm_prompt = """
    Review this sequence of screenshots from a case management system task.
    The user is supposed to delete a case titled "TEST-CASE-REMOVE-ME".
    
    Look for:
    1. A "Delete" button or menu option being clicked.
    2. A confirmation dialog asking "Are you sure?" or similar.
    3. A success message or the case disappearing from the list.
    
    Does the user perform a delete action?
    """
    
    vlm_passed = False
    if frames:
        try:
            vlm_response = query_vlm(
                images=frames,
                prompt=vlm_prompt,
                options=["Yes", "No"]
            )
            
            # Simple heuristic check on VLM response
            # Assuming query_vlm returns a dict or object with text analysis
            # Adjust based on specific VLM implementation
            if isinstance(vlm_response, dict):
                answer = vlm_response.get("answer", "").lower()
                analysis = vlm_response.get("analysis", "").lower()
            else:
                answer = str(vlm_response).lower()
                analysis = ""

            if "yes" in answer or "delete" in analysis:
                score += 20
                vlm_passed = True
                feedback_parts.append("✅ VLM confirmed delete action")
            else:
                feedback_parts.append("⚠️ VLM did not clearly see delete action")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("⚠️ VLM verification skipped due to error")
            # If API confirms deletion, we might be lenient here, but let's stick to strict scoring
            # Or give partial credit if API is 100% correct? 
            # If target is gone, likely they did it. Let's grant 10 pts fallback if API passed.
            if target_gone:
                score += 10

    # Final Calculation
    passed = (score >= 80) and target_gone and control_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }