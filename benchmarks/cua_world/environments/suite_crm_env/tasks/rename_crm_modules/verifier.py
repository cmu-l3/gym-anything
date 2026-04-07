#!/usr/bin/env python3
"""
Verifier for rename_crm_modules task.

Verification Strategy:
1. Primary: Reads the exported JSON from the PHP entryPoint execution to verify that SuiteCRM's
   active `$app_list_strings` cache contains the correctly renamed module labels.
2. Anti-gaming: Checks that the language cache files were modified AFTER the task started.
3. VLM Secondary: Analyzes trajectory frames to verify the agent actually interacted with
   the SuiteCRM UI to make these changes, rather than bypassing the GUI.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_crm_modules(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_acc_sing = metadata.get('expected_accounts_singular', 'Household')
    expected_acc_plur = metadata.get('expected_accounts_plural', 'Households')
    expected_opp_sing = metadata.get('expected_opportunities_singular', 'Investment')
    expected_opp_plur = metadata.get('expected_opportunities_plural', 'Investments')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Check 1: Accounts Singular
    actual_acc_sing = result.get('accounts_singular', '')
    if actual_acc_sing.strip() == expected_acc_sing:
        score += 15
        feedback_parts.append(f"Accounts singular correct ({expected_acc_sing})")
    else:
        feedback_parts.append(f"Accounts singular wrong (Got '{actual_acc_sing}', expected '{expected_acc_sing}')")

    # Check 2: Accounts Plural
    actual_acc_plur = result.get('accounts_plural', '')
    if actual_acc_plur.strip() == expected_acc_plur:
        score += 15
        feedback_parts.append(f"Accounts plural correct ({expected_acc_plur})")
    else:
        feedback_parts.append(f"Accounts plural wrong (Got '{actual_acc_plur}', expected '{expected_acc_plur}')")

    # Check 3: Opportunities Singular
    actual_opp_sing = result.get('opportunities_singular', '')
    if actual_opp_sing.strip() == expected_opp_sing:
        score += 15
        feedback_parts.append(f"Opportunities singular correct ({expected_opp_sing})")
    else:
        feedback_parts.append(f"Opportunities singular wrong (Got '{actual_opp_sing}', expected '{expected_opp_sing}')")

    # Check 4: Opportunities Plural
    actual_opp_plur = result.get('opportunities_plural', '')
    if actual_opp_plur.strip() == expected_opp_plur:
        score += 15
        feedback_parts.append(f"Opportunities plural correct ({expected_opp_plur})")
    else:
        feedback_parts.append(f"Opportunities plural wrong (Got '{actual_opp_plur}', expected '{expected_opp_plur}')")

    # Check 5: Anti-gaming Timestamp Check
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if file_mtime > task_start and task_start > 0:
        score += 20
        feedback_parts.append("Language files were updated during the task execution")
    else:
        feedback_parts.append("Warning: Language files do not appear to have been modified during task execution")

    # Check 6: VLM Trajectory Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames
        
        if images:
            vlm_prompt = (
                "You are auditing an AI agent completing a CRM administration task. "
                "The agent's goal was to navigate to SuiteCRM's 'Rename Modules' admin page, and change the labels "
                "for 'Accounts' to 'Household/Households' and 'Opportunities' to 'Investment/Investments'.\n\n"
                "Review the provided screenshots from the agent's workflow.\n"
                "Did the agent open the 'Rename Modules' UI and type in the new labels? "
                "Respond with a JSON object containing:\n"
                "- 'ui_interaction_found' (boolean): True if the agent navigated to the module renamer and input the text.\n"
                "- 'reasoning' (string): Brief explanation of what is visible in the frames."
            )
            vlm_result = query_vlm(images=images, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get("parsed", {}).get("ui_interaction_found", False):
                vlm_score = 20
                feedback_parts.append("VLM verified correct UI interaction")
            else:
                feedback_parts.append("VLM could not confirm proper interaction with 'Rename Modules' interface")
        else:
            feedback_parts.append("No screenshots available for VLM verification")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification encountered an error")

    score += vlm_score

    # To pass, all 4 labels must be exactly correct (60 pts) + timestamp or VLM confirmation
    labels_correct = (score - vlm_score - (20 if file_mtime > task_start else 0)) == 60
    passed = labels_correct and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }