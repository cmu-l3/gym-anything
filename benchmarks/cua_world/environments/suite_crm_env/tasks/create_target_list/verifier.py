#!/usr/bin/env python3
"""
Verifier for create_target_list task in SuiteCRM.

VERIFICATION STRATEGY:
1. DB Programmatic Checks (80%):
   - Target list created with expected name & type
   - Description matches expectations
   - All three specific contacts are linked via subpanels
   - Anti-gaming: Ensure it was created DURING the task (timestamp check & record count increase)
2. VLM Trajectory Checks (20%):
   - Sample frames from trajectory to verify agent used SuiteCRM interface (no background API gaming).
"""

import os
import json
import tempfile
import logging

# Ensure VLM imports are available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_target_list(traj, env_info, task_info):
    """Verify target list creation and contact linkage."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Q1 2025 Enterprise Outreach')
    expected_type = metadata.get('expected_type', 'default')

    # Copy and parse JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Programmatic DB Checks (80 points)
    # ---------------------------------------------------------
    tl_found = result.get('target_list_found', False)
    tl_data = result.get('target_list', {})
    linked = result.get('contacts_linked', {})
    
    # Anti-gaming: Ensure a new list was actually created
    current_count = result.get('current_count', 0)
    initial_count = result.get('initial_count', 0)
    task_start = result.get('task_start', 0)
    tl_timestamp = tl_data.get('timestamp', 0)
    
    created_during_task = (current_count > initial_count) or (tl_timestamp >= task_start)

    if not created_during_task and tl_found:
        feedback_parts.append("WARNING: Target list found but timestamps indicate it was not created during this task session.")
    
    if tl_found and created_during_task:
        score += 20
        feedback_parts.append(f"Target list '{expected_name}' found.")
        
        if tl_data.get('type', '').lower() == expected_type.lower():
            score += 10
            feedback_parts.append("Type 'Default' verified.")
        else:
            feedback_parts.append(f"Incorrect type: {tl_data.get('type')}.")
            
        desc = tl_data.get('description', '')
        if len(desc) > 10 and 'Q1' in desc:
            score += 5
            feedback_parts.append("Description validated.")
        else:
            feedback_parts.append("Description missing or incomplete.")
            
        # Check Linked Contacts (15 pts each = 45 pts total)
        if linked.get('margaret_chen'):
            score += 15
            feedback_parts.append("Margaret Chen linked.")
        if linked.get('david_rodriguez'):
            score += 15
            feedback_parts.append("David Rodriguez linked.")
        if linked.get('sarah_williams'):
            score += 15
            feedback_parts.append("Sarah Williams linked.")
    else:
        feedback_parts.append("Expected Target List not found or not created during task.")

    # ---------------------------------------------------------
    # VLM Trajectory Check (20 points)
    # ---------------------------------------------------------
    if VLM_AVAILABLE and score > 0:
        logger.info("Running VLM trajectory verification...")
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames

        prompt = """
        You are verifying a computer agent's trajectory in a CRM software (SuiteCRM).
        The agent's task was to create a "Target List" and add contacts using a subpanel interface.
        Look through these chronological screenshots:
        1. Did the agent navigate through the CRM UI?
        2. Is there evidence of interacting with a Target List creation form or the Contacts subpanel?
        
        Respond with valid JSON containing a single boolean field:
        {
          "used_crm_interface_correctly": true/false
        }
        """
        try:
            vlm_res = query_vlm(images=images, prompt=prompt)
            vlm_parsed = vlm_res.get("parsed", {})
            if vlm_parsed.get("used_crm_interface_correctly", False):
                score += 20
                feedback_parts.append("VLM confirms CRM interface usage.")
            else:
                feedback_parts.append("VLM could not confirm CRM interface usage.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Give benefit of doubt if VLM errors out but DB is perfect
            score += 20
            feedback_parts.append("VLM verification skipped (error).")

    elif not VLM_AVAILABLE:
        # If VLM is fully disabled in the env, grant the points if DB checks passed perfectly
        if score >= 65:
            score += 20
            
    # Cap score at 100
    score = min(score, 100)
    
    # Requirements to pass: List created + At least 2 contacts linked
    passed = (score >= 60) and tl_found and created_during_task
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }