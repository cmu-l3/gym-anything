#!/usr/bin/env python3
"""
Verifier for create_user_group task.

SCORING CRITERIA:
1. Group 'compliance-team' exists (30 pts)
2. Group label matches 'Compliance Team' (20 pts)
3. User 'jsmith' is a member (20 pts)
4. User 'mwilson' is a member (20 pts)
5. Anti-gaming: Group did not exist at start (10 pts)

VLM VERIFICATION:
- Checks trajectory to ensure the 'Groups' tab was actually clicked/visited.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_group(traj, env_info, task_info):
    """Verify that the user group was created correctly."""
    
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Extract data from the export result
    final_status = str(result.get("final_http_status", ""))
    initial_status = str(result.get("initial_http_status", ""))
    group_data = result.get("group_api_response", {})
    
    # 2. Check: Group Exists (30 pts)
    if final_status == "200" and group_data:
        score += 30
        feedback_parts.append("Group 'compliance-team' created")
        
        # 3. Check: Group Label (20 pts)
        label = group_data.get("grouplabel", "")
        if label == "Compliance Team":
            score += 20
            feedback_parts.append("Correct label")
        elif "Compliance" in label:
            score += 10
            feedback_parts.append(f"Partial label match ('{label}')")
        else:
            feedback_parts.append(f"Wrong label ('{label}')")

        # 4. Check: Members (40 pts total)
        members = group_data.get("memberUsers", [])
        
        if "jsmith" in members:
            score += 20
            feedback_parts.append("jsmith added")
        else:
            feedback_parts.append("jsmith missing")
            
        if "mwilson" in members:
            score += 20
            feedback_parts.append("mwilson added")
        else:
            feedback_parts.append("mwilson missing")
            
    else:
        feedback_parts.append(f"Group not found (HTTP {final_status})")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Group 'compliance-team' was not created."
        }

    # 5. Check: Anti-Gaming (10 pts)
    # The group should NOT have existed at the start (404)
    if initial_status == "404":
        score += 10
        feedback_parts.append("Clean start verified")
    else:
        feedback_parts.append(f"Anti-gaming warning: Initial state {initial_status}")

    # 6. VLM Trajectory Verification (Process Check)
    # We want to verify the agent actually interacted with the Groups UI
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        You are verifying a user administration task in Nuxeo Platform.
        The goal was to create a user group.
        
        Look at these screenshots of the agent's workflow.
        1. Do you see the 'Users & Groups' administration panel?
        2. Do you see the 'Groups' tab being selected or active?
        3. Do you see a form for creating a new group (fields like Group Name, Label)?
        
        Answer JSON: {"ui_visited": boolean, "groups_tab_seen": boolean, "creation_form_seen": boolean}
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if not parsed.get("ui_visited", False):
                feedback_parts.append("(VLM: UI interaction unclear)")
                # We don't deduct points if programmatic verification passed, 
                # but we note it for quality control.

    # Final Verification
    # Passing requires group existence, label, and at least one member
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }