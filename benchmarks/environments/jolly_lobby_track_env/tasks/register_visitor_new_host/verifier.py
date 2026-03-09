#!/usr/bin/env python3
"""
Verifier for register_visitor_new_host task.

Verifies that the agent:
1. Created a new host record for "Amanda Sterling"
2. Checked in visitor "Jordan Lee"
3. Linked the visitor to the new host

Uses a combination of:
- Database string checks (via export_result.sh)
- VLM trajectory analysis (to verify the "Add Host" workflow was used)
- VLM final state analysis (to verify the visitor is active in the list)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_visitor_new_host(traj, env_info, task_info):
    """
    Verify the visitor registration and host creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic check results
    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task result JSON: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification
    # We need to check two things:
    # A) Did the agent traverse the "Add Host/Employee" screen? (Process)
    # B) Is the visitor successfully signed in with the correct host? (Outcome)

    frames = sample_trajectory_frames(traj, n=5)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No screenshots available"}

    # Combined prompt for efficiency
    prompt = """
    You are verifying a visitor management task.
    
    Goal: Register visitor "Jordan Lee" to see a NEW host "Amanda Sterling".
    
    Please analyze the screenshots (trajectory and final state) to answer:
    1. Is there evidence that the agent opened a "Add Host", "Add Employee", or "New Record" form to add Amanda Sterling? (Look for screens entering "Amanda", "Sterling", "Director of HR").
    2. Does the FINAL screenshot show a list of active/signed-in visitors?
    3. In the final list, is "Jordan Lee" visible?
    4. Is "Jordan Lee" associated with host "Amanda Sterling" (or "Sterling, Amanda")?
    5. Is the status "In", "Checked In", or is there a sign-in time?

    Return JSON:
    {
        "host_creation_seen": true/false,
        "active_list_visible": true/false,
        "visitor_name_correct": true/false,
        "host_association_correct": true/false,
        "checked_in_status": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_response = query_vlm(images=frames + [final_screenshot], prompt=prompt)
    vlm_data = vlm_response.get('parsed', {})
    
    # 3. Scoring Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: Database Evidence (30 points)
    # Checking if data was actually written to disk
    if result_data.get('host_string_in_db', False):
        score += 15
        feedback_parts.append("Host record saved to DB (+15)")
    if result_data.get('visitor_string_in_db', False):
        score += 15
        feedback_parts.append("Visitor record saved to DB (+15)")
        
    # Criterion 2: Process Verification (VLM) (30 points)
    if vlm_data.get('host_creation_seen', False):
        score += 30
        feedback_parts.append("Host creation workflow observed (+30)")
    else:
        feedback_parts.append("Host creation workflow NOT observed (0)")

    # Criterion 3: Final State Verification (VLM) (40 points)
    final_state_ok = (
        vlm_data.get('active_list_visible', False) and
        vlm_data.get('visitor_name_correct', False) and
        vlm_data.get('checked_in_status', False)
    )
    
    host_link_ok = vlm_data.get('host_association_correct', False)

    if final_state_ok:
        score += 20
        feedback_parts.append("Visitor successfully checked in (+20)")
        if host_link_ok:
            score += 20
            feedback_parts.append("Visitor correctly linked to new host (+20)")
        else:
            feedback_parts.append("Visitor checked in but WRONG host linked (0)")
    else:
        feedback_parts.append("Visitor NOT found in active list (0)")

    # Pass logic
    passed = score >= 80  # Requires most steps to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "details": {
            "vlm_analysis": vlm_data,
            "db_check": result_data
        }
    }