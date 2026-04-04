#!/usr/bin/env python3
"""
Verifier for perform_conflict_check task.

Verification Strategy:
1. Load the task result JSON (exported from the container).
2. Check if the "New Case" has a note containing specific keywords.
3. CRITICAL: Verify the note contains the correct "Old Case ID" (anti-gaming).
4. Verify VLM trajectory to ensure search was performed.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_conflict_check(traj, env_info, task_info):
    """
    Verify the agent performed the conflict check and logged the note correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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

    # Extract Data
    notes_text = result.get("extracted_notes", "")
    old_case_id = result.get("old_case_id", "")
    new_case_id = result.get("new_case_id", "")
    
    score = 0
    feedback_parts = []
    
    # 2. Check Note Existence & Keywords (50 points)
    if not notes_text:
        feedback_parts.append("No notes found on the new case.")
    else:
        # Check for 'Conflict' (20 pts)
        if "conflict" in notes_text.lower():
            score += 20
            feedback_parts.append("Keyword 'Conflict' found")
        else:
            feedback_parts.append("Keyword 'Conflict' missing")

        # Check for Investigator Name (10 pts)
        if "elena" in notes_text.lower() or "fisher" in notes_text.lower():
            score += 10
            feedback_parts.append("Investigator name found")
        else:
            feedback_parts.append("Investigator name missing")

        # Check for specific phrase structure (20 pts)
        if "conflict detected" in notes_text.lower():
            score += 20
            feedback_parts.append("Exact phrase 'Conflict Detected' found")

    # 3. Check for Correct Case ID (30 points) - The specific "Needle"
    if old_case_id and old_case_id in notes_text:
        score += 30
        feedback_parts.append(f"Correct Historical Case ID ({old_case_id}) referenced")
    else:
        feedback_parts.append(f"Historical Case ID ({old_case_id}) NOT found in notes")

    # 4. VLM Verification (20 points)
    # Did the agent actually search and look at the old case?
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames and query_vlm:
        prompt = f"""
        Did the agent:
        1. Search for 'Drake Antiquities'?
        2. View a case list or search results?
        3. Navigate to a case detail view?
        
        Look at the sequence of images.
        """
        # We query the VLM
        try:
            vlm_resp = query_vlm(images=frames + [final_shot], prompt=prompt)
            if vlm_resp.get("success"):
                # Simple heuristic: if VLM says yes/positive analysis
                analysis = vlm_resp.get("response", "").lower()
                if "yes" in analysis or "searched" in analysis:
                    vlm_score = 20
                    feedback_parts.append("VLM confirmed search workflow")
                else:
                    # Fallback partial points if ambiguous
                    vlm_score = 10 
            else:
                vlm_score = 0
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            vlm_score = 0
            
    score += vlm_score

    # Final Pass Logic
    # Must have the correct Case ID + "Conflict" keyword to pass
    critical_success = (old_case_id in notes_text) and ("conflict" in notes_text.lower())
    passed = (score >= 80) and critical_success

    if passed:
        feedback_parts.append("Task Completed Successfully")
    elif critical_success:
        feedback_parts.append("Critical steps done but score too low")
    else:
        feedback_parts.append("Failed critical criteria (Case ID match)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }