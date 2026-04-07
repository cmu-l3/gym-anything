#!/usr/bin/env python3
"""
Verifier for enable_version_hierarchy task.

Criteria:
1. "Orbital Platform" project version "Phase 1 Launch" sharing is NOT 'none' (40 pts)
   - Accepted values: 'descendants', 'hierarchy', 'tree', 'system'
2. "Propulsion System" issue "Main Thruster Design" is assigned to that version (40 pts)
   - issue.fixed_version_id == version.id
3. VLM Verification of workflow (20 pts)
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_version_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback = []
    
    # ----------------------------------------------------------------
    # 1. Verify Version Sharing (40 points)
    # ----------------------------------------------------------------
    sharing_status = db_state.get('version_sharing', 'none')
    allowed_values = metadata.get('sharing_values_allowed', ['descendants', 'hierarchy', 'tree', 'system'])
    
    if sharing_status in allowed_values:
        score += 40
        feedback.append(f"Success: Version sharing enabled (mode: '{sharing_status}').")
    elif sharing_status == 'none':
        feedback.append("Fail: Version sharing is still set to 'none'. Parent versions are not visible to subprojects.")
    else:
        feedback.append(f"Fail: Unexpected sharing status '{sharing_status}'.")

    # ----------------------------------------------------------------
    # 2. Verify Issue Assignment (40 points)
    # ----------------------------------------------------------------
    version_id = db_state.get('version_id')
    issue_fixed_version_id = db_state.get('issue_fixed_version_id')
    
    # Only check this if version_id is valid
    if version_id and issue_fixed_version_id == version_id:
        score += 40
        feedback.append("Success: Issue is correctly assigned to 'Phase 1 Launch'.")
    else:
        if issue_fixed_version_id is None:
            feedback.append("Fail: Issue 'Main Thruster Design' has no target version assigned.")
        elif issue_fixed_version_id != version_id:
            feedback.append(f"Fail: Issue assigned to wrong version ID (Expected {version_id}, got {issue_fixed_version_id}).")

    # ----------------------------------------------------------------
    # 3. VLM Trajectory Verification (20 points)
    # ----------------------------------------------------------------
    # We want to see if the agent navigated to settings and interacted with the sharing dropdown
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a user interacting with Redmine.
        The user goal is to:
        1. Go to Project Settings -> Versions (or Information) tab.
        2. Change a Version's 'Sharing' setting from 'None' to 'With subprojects'.
        3. Go to an Issue and select that Version in the dropdown.
        
        Do you see evidence of:
        - The Project Settings page?
        - A 'Sharing' dropdown menu being clicked or changed?
        - An Issue editing form?
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success"):
                # Basic sentiment check - if VLM confirms relevant screens, award points
                # This is soft verification to reward process
                analysis = vlm_res.get("response", "").lower()
                if "settings" in analysis or "sharing" in analysis or "dropdown" in analysis:
                    score += 20
                    feedback.append("VLM: Workflow verified (settings interaction detected).")
                else:
                    # Partial credit if they at least attempted
                    score += 10 
                    feedback.append("VLM: Workflow unclear, but screens visited.")
            else:
                score += 10 # Grace points if VLM fails but logic passed
        except:
            score += 0 # No penalty, just no bonus
            
    else:
        feedback.append("No trajectory frames available for visual verification.")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = (score >= 80) # Must pass both technical checks (40+40)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }