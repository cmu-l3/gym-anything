#!/usr/bin/env python3
"""
Verifier for search_and_update_case_priority task.

Criteria:
1. API Verification: Target case priority must be "High" (35 pts)
2. API Verification: Target case title must match (sanity check) (10 pts)
3. Anti-Gaming: Priority must have changed from "Low" (10 pts)
4. VLM Verification: Agent searched for case (15 pts)
5. VLM Verification: Agent navigated to details (15 pts)
6. VLM Verification: Agent interacted with priority field (15 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_search_and_update_case_priority(traj, env_info, task_info):
    """
    Verifies that the agent found the specific case and updated its priority.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_priority = metadata.get('target_priority', 'High')
    target_title_substr = "EPA Region 5" # Key identifier

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    current_priority = result.get('current_priority', '')
    initial_priority = result.get('initial_priority', '')
    current_title = result.get('current_title', '')

    # 2. Programmatic Verification (55 points max)
    
    # Check 1: Priority Update (35 pts)
    if current_priority == target_priority:
        score += 35
        feedback_parts.append("✅ Priority updated to High.")
    else:
        feedback_parts.append(f"❌ Priority is '{current_priority}', expected '{target_priority}'.")

    # Check 2: Correct Case Modified (10 pts)
    if target_title_substr in current_title:
        score += 10
        feedback_parts.append("✅ Modified correct case title.")
    else:
        feedback_parts.append(f"❌ Modified wrong case (Title: {current_title}).")

    # Check 3: Anti-Gaming / State Change (10 pts)
    if initial_priority == "Low" and current_priority != "Low":
        score += 10
        feedback_parts.append("✅ Priority value actually changed.")
    elif initial_priority == current_priority:
        feedback_parts.append("⚠️ Priority value did not change.")

    # 3. VLM Verification (45 points max)
    # We verify the workflow: Search -> Select -> Edit
    
    frames = sample_trajectory_frames(traj, n=5)
    final_shot = get_final_screenshot(traj)
    
    if not frames:
        feedback_parts.append("❌ No trajectory frames available for VLM.")
    else:
        vlm_prompt = """
        You are verifying an agent's workflow in a Case Management System (ArkCase).
        The goal was to:
        1. Search for a case titled 'Delayed Public Records Response - EPA Region 5'.
        2. Open the case details.
        3. Change Priority to 'High'.

        Review the screenshots provided.
        1. Did the agent use a search bar or search filter?
        2. Did the agent open a specific case detail view (showing fields like Title, Status, Priority)?
        3. Is there evidence of changing the Priority dropdown or saving the case?

        Return JSON:
        {
            "search_performed": boolean,
            "details_opened": boolean,
            "priority_edited": boolean,
            "explanation": "brief reasoning"
        }
        """
        
        # Combine images for VLM (frames + final)
        images_to_check = frames + ([final_shot] if final_shot else [])
        
        try:
            vlm_res = query_vlm(images=images_to_check, prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('search_performed'):
                score += 15
                feedback_parts.append("✅ VLM: Search workflow detected.")
            else:
                feedback_parts.append("❌ VLM: No search detected.")
                
            if parsed.get('details_opened'):
                score += 15
                feedback_parts.append("✅ VLM: Case details opened.")
            else:
                feedback_parts.append("❌ VLM: Case details not seen.")
                
            if parsed.get('priority_edited'):
                score += 15
                feedback_parts.append("✅ VLM: Priority edit interaction detected.")
            else:
                feedback_parts.append("❌ VLM: Priority edit not clearly seen.")
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("⚠️ VLM verification skipped due to error.")

    # 4. Final Scoring
    # Pass threshold: 55 points AND Priority must be High
    passed = (score >= 55) and (current_priority == target_priority)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }