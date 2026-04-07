#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_custom_log_field(traj, env_info, task_info):
    """
    Verifies that the agent created a custom field extraction for 'FinTransactionID'.
    
    Criteria:
    1. Configuration Persistence (40 pts): 'FinTransactionID' found in ELA config files or DB.
    2. Regex Validity (40 pts): The configuration contains the 'TXN' pattern fragment.
    3. Visual Verification (20 pts): VLM confirms agent interacted with Field Extraction UI.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    score = 0
    feedback = []
    
    # 1. Load System Evidence
    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Verify Field Existence (Config or DB)
    conf_match = result_data.get("conf_match", "")
    db_found = result_data.get("db_record_found") == "true"
    modified_during = result_data.get("file_modified_during_task")
    
    field_exists = False
    if "FinTransactionID" in conf_match or db_found:
        field_exists = True
        
    if field_exists:
        # Anti-gaming: Ensure it was created/modified during this session
        # If DB found it but we can't check timestamp easily, we rely on init script clearing/checking state
        # But here 'file_modified_during_task' is a strong signal for the conf file method
        if modified_during or db_found: 
            score += 40
            feedback.append("Success: 'FinTransactionID' field configuration found.")
        else:
            score += 20
            feedback.append("Warning: Field found but timestamp verification inconclusive.")
    else:
        feedback.append("Fail: 'FinTransactionID' configuration not found in system files or database.")

    # 3. Verify Regex Pattern
    # We look for evidence that the agent actually targeted the correct data pattern
    regex_evidence = result_data.get("regex_match", "")
    db_data = result_data.get("db_data", "")
    
    has_regex = False
    if "TXN" in regex_evidence or "TXN" in db_data:
        has_regex = True
    
    if has_regex:
        score += 40
        feedback.append("Success: Regex pattern for 'TXN' ID found.")
    else:
        feedback.append("Fail: No evidence of correct Regex pattern ('TXN') in configuration.")

    # 4. VLM Verification (Trajectory)
    # We check if the agent actually used the UI workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "You are verifying a user action in ManageEngine EventLog Analyzer.\n"
        "The user should be creating a 'Custom Field' or 'Extracted Field'.\n"
        "Look for:\n"
        "1. A dialog or screen titled 'Extract Field', 'Custom Patterns', or similar.\n"
        "2. An input field where 'FinTransactionID' is typed.\n"
        "3. A regex input where something like 'TXN' is typed.\n"
        "Did the user perform these actions?"
    )
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        if vlm_res and vlm_res.get('success'):
            analysis = vlm_res.get('response', '').lower()
            if "yes" in analysis or "performed" in analysis:
                vlm_score = 20
                feedback.append("Visual: VLM confirms UI workflow for field extraction.")
            else:
                feedback.append("Visual: VLM could not clearly confirm the field extraction workflow.")
    except Exception:
        feedback.append("Visual: Verification skipped due to VLM error.")
        vlm_score = 10 # Give benefit of doubt if VLM fails but logic passed
        
    score += vlm_score

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }