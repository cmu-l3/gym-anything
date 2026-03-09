#!/usr/bin/env python3
"""
Verifier for delete_employee_host task.
Uses VLM to verify the visual state of the application and file timestamps for anti-gaming.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_employee_host(traj, env_info, task_info):
    """
    Verify that the agent deleted 'Sarah Chen' from the host list.
    
    Criteria:
    1. Navigation: Agent accessed the Host/Employee list (VLM trajectory).
    2. Deletion: 'Sarah Chen' is NO LONGER visible in the list (VLM final).
    3. Safety: 'Michael Torres' and 'Priya Kapoor' ARE still visible (VLM final).
    4. Action: Database file was modified (Anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load export results
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Check Anti-Gaming (File Modification)
    db_modified = task_result.get('db_modified', False)
    db_size_changed = task_result.get('db_size_changed', False)
    
    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available"}

    # Prompt for VLM
    prompt = """
    You are verifying a task in 'Jolly Lobby Track' visitor management software.
    The goal was to DELETE the host 'Sarah Chen' from the list.
    The list should still contain 'Michael Torres' and 'Priya Kapoor'.

    Review the screenshots (trajectory and final state):
    1. Did the agent navigate to a list of Employees or Hosts?
    2. In the FINAL screenshot, is 'Sarah Chen' visible in the list? (She should NOT be there).
    3. In the FINAL screenshot, are 'Michael Torres' and 'Priya Kapoor' visible? (They SHOULD be there).
    4. Did the agent show a confirmation dialog for deletion?

    Output valid JSON:
    {
        "navigated_to_list": true/false,
        "sarah_chen_visible_in_final": true/false,
        "michael_torres_visible_in_final": true/false,
        "priya_kapoor_visible_in_final": true/false,
        "deletion_confirmed": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_response = query_vlm(images=frames + [final_screenshot], prompt=prompt)
    
    if not vlm_response.get('success'):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed"}
        
    data = vlm_response.get('parsed', {})
    
    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Navigation (20 pts)
    if data.get('navigated_to_list'):
        score += 20
        feedback_parts.append("Navigated to host list")
    
    # Criterion 2: Sarah Chen GONE (40 pts) - CRITICAL
    if not data.get('sarah_chen_visible_in_final'):
        score += 40
        feedback_parts.append("Sarah Chen successfully removed")
    else:
        feedback_parts.append("FAIL: Sarah Chen still visible")
        
    # Criterion 3: Others REMAIN (20 pts)
    others_present = data.get('michael_torres_visible_in_final') and data.get('priya_kapoor_visible_in_final')
    if others_present:
        score += 20
        feedback_parts.append("Other hosts preserved")
    else:
        feedback_parts.append("WARNING: Other hosts missing")

    # Criterion 4: DB Modified (20 pts)
    if db_modified or db_size_changed:
        score += 20
        feedback_parts.append("Database file modified")
    else:
        feedback_parts.append("No database changes detected")
        
    passed = score >= 80 and not data.get('sarah_chen_visible_in_final')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }