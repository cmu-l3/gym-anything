#!/usr/bin/env python3
"""
Verifier for add_police_department task.

Verification Strategy:
1. Anti-Gaming: Check if CAMEO database file was modified during the task.
2. VLM Verification: Analyze trajectory and final state to confirm:
   - Agent navigated to Police Department resources
   - "Maplewood Township Police Department" name is visible
   - Details (Address, Phone, etc.) are entered correctly
   - Record was saved/listed
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt(metadata):
    return f"""
You are verifying a task in CAMEO Data Manager.
Goal: Add a Police Department resource.

Expected Details:
- Name: {metadata.get('expected_name')}
- Address: {metadata.get('expected_address')}
- City/State: {metadata.get('expected_city')}, {metadata.get('expected_state')}
- Phone: {metadata.get('expected_phone')}
- Contact: {metadata.get('expected_contact')}

Examine the screenshots (trajectory and final state) and determine:
1. Did the agent navigate to the "Police Departments" or "Resources" section?
2. Is the name "{metadata.get('expected_name')}" visible in a form or list?
3. Are the address or contact details visible and correct?
4. Is there evidence the record was saved (e.g., appearing in a list, "Record Saved" message, or simple completion of the form followed by a save action)?

Return JSON:
{{
  "navigated_to_resources": true/false,
  "name_visible": true/false,
  "details_match": true/false,
  "record_saved": true/false,
  "confidence": "high/medium/low",
  "explanation": "..."
}}
"""


def verify_add_police_department(traj, env_info, task_info):
    """
    Verify the add_police_department task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve programmatic result (File stats)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        file_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Programmatic Checks (Anti-gaming)
    score = 0
    feedback_parts = []
    
    db_modified = file_result.get('db_modified_during_task', False)
    app_running = file_result.get('app_running', False)

    if app_running:
        score += 10
        feedback_parts.append("Application is running.")
    
    if db_modified:
        score += 20
        feedback_parts.append("Database modified during task (activity detected).")
    else:
        feedback_parts.append("Warning: Database file not modified.")

    # 3. VLM Verification (Visual proof of work)
    # We use the trajectory frames to capture the form entry process
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    prompt = build_vlm_prompt(metadata)
    vlm_response = query_vlm(prompt=prompt, images=frames)
    
    if vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        
        # Scoring based on visual evidence
        if parsed.get("navigated_to_resources"):
            score += 20
            feedback_parts.append("Correctly navigated to resources.")
        
        if parsed.get("name_visible"):
            score += 25
            feedback_parts.append("Police Department name verified visually.")
        
        if parsed.get("details_match"):
            score += 15
            feedback_parts.append("Contact/Address details matched visually.")
            
        if parsed.get("record_saved"):
            score += 10
            feedback_parts.append("Record appears to be saved.")
            
        feedback_parts.append(f"VLM Explanation: {parsed.get('explanation')}")
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # Final Pass/Fail determination
    # Must have modified DB AND visual confirmation of the name
    passed = (db_modified or score >= 80) and score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }