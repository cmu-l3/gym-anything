#!/usr/bin/env python3
"""
Verifier for assign_group_badge_template task.

Verification Strategy:
1. Anti-Gaming: Check if the database/configuration file was actually modified (saved).
2. VLM Trajectory: Analyze screenshots to confirm the agent:
   - Accessed settings/groups menu
   - Selected 'Contractor'
   - Selected 'Visitor - Vertical' badge template
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt designed to detect the specific configuration steps
VLM_PROMPT = """
You are verifying an agent's actions in the Jolly Lobby Track software.
The goal was to configure the "Contractor" visitor group to use the "Visitor - Vertical" badge template.

Review the sequence of screenshots and determine if the following steps were performed:
1. Did the agent navigate to a Settings, Options, or Rules/Groups configuration screen?
2. Did the agent select or highlight the "Contractor" group/category?
3. Did the agent select "Visitor - Vertical" (or just "Vertical") in a Badge Template or Card Design dropdown/menu?
4. Did the agent attempt to save or apply the changes (e.g., clicking OK, Save, or closing the dialog)?

Focus on text visible in dropdowns, lists, and configuration panels.

Return your assessment in JSON format:
{
  "settings_opened": boolean,
  "contractor_group_selected": boolean,
  "vertical_template_selected": boolean,
  "changes_saved": boolean,
  "confidence": "low|medium|high",
  "reasoning": "Brief explanation of what was observed"
}
"""

def verify_assign_group_badge_template(traj, env_info, task_info):
    """
    Verifies that the agent assigned the vertical badge template to the contractor group.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results (File modification check)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_modified = result_data.get("db_modified", False)
    
    # 2. VLM Verification
    # Sample frames from the trajectory to capture the workflow
    frames = sample_trajectory_frames(traj, n=8)
    
    # If no frames, we can't verify
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available for verification"}

    vlm_response = query_vlm(
        images=frames,
        prompt=VLM_PROMPT
    )
    
    if not vlm_response or "parsed" not in vlm_response:
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to process images"}

    vlm_data = vlm_response["parsed"]
    
    # 3. Scoring
    score = 0
    feedback_parts = []

    # Criterion A: Navigation (20 pts)
    if vlm_data.get("settings_opened"):
        score += 20
        feedback_parts.append("Found settings menu")
    else:
        feedback_parts.append("Failed to find settings menu")

    # Criterion B: Group Selection (20 pts)
    if vlm_data.get("contractor_group_selected"):
        score += 20
        feedback_parts.append("Selected 'Contractor' group")
    else:
        feedback_parts.append("Did not select 'Contractor' group")

    # Criterion C: Template Assignment (40 pts)
    if vlm_data.get("vertical_template_selected"):
        score += 40
        feedback_parts.append("Selected 'Vertical' template")
    else:
        feedback_parts.append("Did not select correct badge template")

    # Criterion D: Persistence/Save (20 pts)
    # Require BOTH visual confirmation of save/apply AND file modification on disk
    if vlm_data.get("changes_saved") and db_modified:
        score += 20
        feedback_parts.append("Changes saved and persisted to disk")
    elif vlm_data.get("changes_saved") and not db_modified:
        score += 10
        feedback_parts.append("Clicked save but no disk write detected (possible partial success)")
    elif db_modified and not vlm_data.get("changes_saved"):
        score += 10
        feedback_parts.append("File modified but save action not visually confirmed")
    else:
        feedback_parts.append("Changes not saved")

    # Pass/Fail determination
    # Must have selected the correct template and group to pass
    critical_success = (vlm_data.get("contractor_group_selected") and 
                        vlm_data.get("vertical_template_selected"))
    
    passed = (score >= 80) and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts) + f". Reasoning: {vlm_data.get('reasoning', 'N/A')}"
    }