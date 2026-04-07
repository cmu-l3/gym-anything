#!/usr/bin/env python3
"""
Verifier for delete_calendar_event task.
Checks if the specified calendar event was removed from the database
and verifies the workflow using VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_calendar_event(traj, env_info, task_info):
    """
    Verify deletion of 'Sales Pipeline Sync' event.
    
    Scoring:
    - 40 pts: Event ID no longer exists in DB
    - 20 pts: Total event count decreased by exactly 1
    - 10 pts: Event name no longer found in DB
    - 30 pts: VLM verification of deletion workflow
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Database Verification
    if not result.get('odoo_accessible'):
        return {"passed": False, "score": 0, "feedback": "Could not access Odoo database for verification"}
        
    # Check specific ID (Primary Proof)
    target_exists_id = result.get('target_still_exists_by_id', True)
    if not target_exists_id:
        score += 40
        feedback_parts.append("Target event ID successfully removed (+40)")
    else:
        feedback_parts.append("Target event ID still exists in database")
        
    # Check count delta (Collateral Damage Check)
    delta = result.get('count_delta', 0)
    if delta == -1:
        score += 20
        feedback_parts.append("Event count decreased by exactly 1 (+20)")
    elif delta < -1:
        score += 10
        feedback_parts.append(f"Event count decreased by {abs(delta)} (warning: deleted extra events) (+10)")
    else:
        feedback_parts.append(f"Event count delta is {delta} (expected -1)")

    # Check name existence (Sanity Check)
    target_exists_name = result.get('target_still_exists_by_name', True)
    if not target_exists_name:
        score += 10
        feedback_parts.append("Event name 'Sales Pipeline Sync' no longer found (+10)")
    
    # 2. VLM Verification
    vlm_score = 0
    try:
        # Sample frames from the trajectory
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = """
        You are verifying a user action in Odoo Calendar. The user was tasked with DELETING a meeting named 'Sales Pipeline Sync'.
        
        Analyze the sequence of screenshots to determine if the deletion workflow was performed.
        Look for:
        1. Navigation to a calendar view (Week, Month, or Day).
        2. A popover or details modal for an event named "Sales Pipeline Sync".
        3. A click on a 'Delete' or 'Remove' button (trash icon or 'Delete' text).
        4. A confirmation dialog asking "Are you sure?" or similar.
        5. The event disappearing from the view.
        
        Respond in JSON:
        {
            "calendar_visible": boolean,
            "event_selected": boolean,
            "delete_action_observed": boolean,
            "confirmation_observed": boolean,
            "confidence": "low|medium|high"
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=frames)
        
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            logger.info(f"VLM Analysis: {parsed}")
            
            if parsed.get('delete_action_observed') or parsed.get('confirmation_observed'):
                vlm_score += 30
                feedback_parts.append("VLM confirmed deletion workflow (+30)")
            elif parsed.get('event_selected'):
                vlm_score += 10
                feedback_parts.append("VLM confirmed event selection but deletion unclear (+10)")
            elif parsed.get('calendar_visible'):
                vlm_score += 5
                feedback_parts.append("VLM confirmed calendar navigation (+5)")
        else:
            feedback_parts.append("VLM verification failed to run")
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append("VLM verification error")
        
    score += vlm_score
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }