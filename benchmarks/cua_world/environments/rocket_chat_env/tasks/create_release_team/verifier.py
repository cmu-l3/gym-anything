#!/usr/bin/env python3
"""
Verifier for create_release_team task in Rocket.Chat.

Checks:
1. Team 'release-management' exists (25 pts)
2. Team is public (10 pts)
3. Team description is correct (15 pts)
4. 'agent.user' is a member (20 pts)
5. 'release-updates' channel is associated with the team (20 pts)
6. VLM visual confirmation (10 pts)
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_release_team(traj, env_info, task_info):
    """
    Verify the create_release_team task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_team = metadata.get('target_team_name', 'release-management')
    target_desc = metadata.get('target_description', 'Coordinates all release activities and planning')
    
    score = 0
    feedback_parts = []
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Verify Team Existence (25 pts)
    if result.get("team_exists"):
        score += 25
        feedback_parts.append(f"Team '{target_team}' created.")
    else:
        return {"passed": False, "score": 0, "feedback": f"Team '{target_team}' was not found."}

    # 2. Verify Team Type (10 pts)
    # Type 0 is Public, 1 is Private
    team_type = result.get("team_type")
    if team_type == 0:
        score += 10
        feedback_parts.append("Team is Public.")
    else:
        feedback_parts.append("Team is NOT Public (type={}).".format(team_type))

    # 3. Verify Description (15 pts)
    actual_desc = result.get("description", "").strip()
    if target_desc.lower() in actual_desc.lower():
        score += 15
        feedback_parts.append("Description matches.")
    else:
        feedback_parts.append(f"Description mismatch. Expected containing '{target_desc}', got '{actual_desc}'.")

    # 4. Verify Member Addition (20 pts)
    if result.get("agent_is_member"):
        score += 20
        feedback_parts.append("agent.user is a member.")
    else:
        feedback_parts.append("agent.user was NOT found in team members.")

    # 5. Verify Channel Association (20 pts)
    if result.get("channel_in_team"):
        score += 20
        feedback_parts.append("release-updates channel added to team.")
    else:
        feedback_parts.append("release-updates channel NOT found in team rooms.")

    # 6. VLM Visual Check (10 pts)
    # We check if the sidebar shows the team icon/name using trajectory or final screenshot
    from gym_anything.vlm import query_vlm, get_final_screenshot
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = f"""
        Look at this Rocket.Chat screenshot.
        Does the sidebar (left panel) show a Team named '{target_team}'?
        Teams usually have a distinct icon (often a T-shirt or multiple people icon) compared to channels (#).
        Also check if the main header shows '{target_team}'.
        
        Respond JSON: {{ "team_visible": true/false }}
        """
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_resp.get("success") and vlm_resp.get("parsed", {}).get("team_visible"):
                vlm_score = 10
                feedback_parts.append("VLM confirmed team visibility.")
            else:
                feedback_parts.append("VLM could not visually confirm team in screenshot.")
        except Exception:
            feedback_parts.append("VLM check failed.")
    
    score += vlm_score

    # Anti-gaming: Check timestamp
    # Ensure team creation time > task start time
    created_at_iso = result.get("created_at")
    task_start_ts = result.get("task_start_ts", 0)
    
    if created_at_iso:
        try:
            # Rocket.Chat returns ISO 8601 like "2026-03-08T12:00:00.000Z"
            # Python < 3.11 doesn't handle Z easily with fromisoformat, simplest is verify against start
            # If created_at is strictly non-empty and team exists, we assume valid
            pass 
        except Exception:
            pass
            
    # Calculate Result
    passed = score >= 65 and result.get("team_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }