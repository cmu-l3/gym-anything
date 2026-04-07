#!/usr/bin/env python3
"""
Verifier for create_segmented_target_list task.

VERIFICATION STRATEGY:
1. Programmatic DB Check (75 pts):
   - Target List created
   - Correct filtering applied (Data Leakage checks)
   - Proper extraction count (5 Seattle contacts)
2. VLM Trajectory Check (25 pts):
   - Confirms workflow visually (used filter, used bulk action)
   
Anti-gaming: If an agent bypasses the filter and just adds ALL contacts to 
the list, they will trigger a massive penalty on the data leakage check and fail.
"""

import json
import os
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("gym_anything.vlm not available. VLM checks will be skipped.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are analyzing screenshots from a CRM interaction to verify proper workflow usage.
Did the user perform the following actions?
1. Open or use the 'Filter' (Advanced Search) panel in the Contacts module.
2. Open the 'Bulk Action' menu to add selected records to a Target List.

Respond with a JSON object containing two boolean fields:
{
    "used_filter_panel": true/false,
    "used_bulk_action": true/false
}
"""

def verify_create_segmented_target_list(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON results
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
    
    list_found = result.get('list_found', False)
    seattle_count = result.get('seattle_contacts_linked', 0)
    non_seattle_count = result.get('non_seattle_contacts_linked', 0)

    # 1. Target List Creation (10 pts)
    if list_found:
        score += 10
        feedback_parts.append("Target List 'Seattle Regional Campaign' created")
    else:
        feedback_parts.append("Target List not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Minimum acceptable Seattle contacts linked (15 pts)
    if seattle_count >= 4:
        score += 15
        feedback_parts.append(f"Valid extraction ({seattle_count}/5 Seattle contacts)")
    elif seattle_count > 0:
        score += 5
        feedback_parts.append(f"Partial extraction ({seattle_count}/5 Seattle contacts)")
    else:
        feedback_parts.append("No Seattle contacts linked")

    # 3. Data Leakage / Filter Application Check (30 pts)
    # CRITICAL: This checks if they actually filtered or just selected everyone
    if non_seattle_count == 0 and seattle_count > 0:
        score += 30
        feedback_parts.append("Zero data leakage (proper filtering used)")
    else:
        feedback_parts.append(f"FAIL: Data leakage detected! {non_seattle_count} non-Seattle contacts included")

    # 4. Perfect Extraction (20 pts)
    if seattle_count == 5 and non_seattle_count == 0:
        score += 20
        feedback_parts.append("Perfect extraction (all 5 contacts found)")

    # 5. VLM Trajectory Analysis (25 pts)
    vlm_points = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_resp = query_vlm(images=images, prompt=VLM_PROMPT)
                vlm_parsed = vlm_resp.get("parsed", {})
                
                if vlm_parsed.get("used_filter_panel", False):
                    vlm_points += 15
                    feedback_parts.append("VLM: Filter panel usage verified")
                else:
                    feedback_parts.append("VLM: Filter panel usage not detected")
                    
                if vlm_parsed.get("used_bulk_action", False):
                    vlm_points += 10
                    feedback_parts.append("VLM: Bulk action usage verified")
                else:
                    feedback_parts.append("VLM: Bulk action usage not detected")
            
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM check skipped/failed")
    else:
        # Give grace points if VLM is unavailable but perfect DB extraction exists
        if seattle_count == 5 and non_seattle_count == 0:
            vlm_points = 25
            feedback_parts.append("VLM unavailable; granting points due to perfect DB state")

    score += vlm_points
    
    # Final Evaluation (Must hit 60 points AND have zero data leakage)
    key_criteria_met = list_found and (non_seattle_count == 0) and (seattle_count >= 4)
    passed = (score >= 60) and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("Critical Failure: Either list missing, inadequate contacts, or leakage detected.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }