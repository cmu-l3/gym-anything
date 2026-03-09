#!/usr/bin/env python3
"""
Verifier for link_related_requests task.

Verifies that the agent has successfully created a relationship link between
two specific service requests in ServiceDesk Plus.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_related_requests(traj, env_info, task_info):
    """
    Verify the linking of two requests.
    
    Criteria:
    1. Database confirmation of link record (WorkOrderToWorkOrder) - PRIMARY
    2. VLM confirmation of UI interaction/state - SECONDARY
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
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
            
    # 2. Verify Database Link (60 points)
    link_count = int(result.get("link_count", 0))
    req_a = result.get("request_a_id")
    req_b = result.get("request_b_id")
    
    if link_count > 0:
        score += 60
        feedback_parts.append(f"SUCCESS: Database confirms link between Request {req_a} and {req_b}.")
    else:
        feedback_parts.append("FAILURE: No relationship record found in database.")

    # 3. VLM Verification (40 points)
    # We check if the agent actually navigated to the relations tab
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an IT Service Desk agent's workflow.
    The goal is to link two requests together as 'Related'.
    
    Look at the screenshots.
    1. Did the agent navigate to a Request details page? (Look for 'Request Details', 'Subject', or ID)
    2. Did the agent access the 'Relations' or 'Link' tab/section?
    3. Is there visual evidence of a linked request in the final state?
    
    Return JSON:
    {
        "request_view_reached": true/false,
        "relations_tab_accessed": true/false,
        "link_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("request_view_reached"):
            score += 10
            feedback_parts.append("VLM: Agent navigated to request details.")
        
        if parsed.get("relations_tab_accessed"):
            score += 10
            feedback_parts.append("VLM: Agent accessed Relations tab.")
            
        if parsed.get("link_visible"):
            score += 20
            feedback_parts.append("VLM: Linked request visible in final screenshot.")
            vlm_passed = True
    else:
        feedback_parts.append("VLM verification failed or inconclusive.")

    # 4. Final Determination
    # Must have DB confirmation OR strong VLM evidence (in case DB query logic has edge cases)
    # But for this task, DB is the gold standard.
    
    passed = (link_count > 0) and (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }