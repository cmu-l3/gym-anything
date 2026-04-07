#!/usr/bin/env python3
"""
Verifier for configure_azure_tenant task.

Verification Strategy:
1. Log Evidence (30 pts): Check if the tenant name 'northwindtraders.onmicrosoft.com' appears in ADAudit Plus logs.
   This confirms the user attempted to save the configuration (even if it failed due to connection).
2. VLM Trajectory (70 pts): Visually verify the workflow steps:
   - Navigated to Cloud Directory/Configuration
   - Entered correct Tenant Name
   - Entered correct Client ID
   - Entered correct Client Secret (if visible/masked)
   - Clicked Save/Add

Anti-gaming:
- Requires specific non-trivial strings to be entered.
- Log timestamp check ensures it happened during the task.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_azure_tenant(traj, env_info, task_info):
    """
    Verify the Azure Tenant configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tenant = metadata.get('tenant_name', "northwindtraders.onmicrosoft.com")
    expected_client_id = metadata.get('client_id', "d87c3e2a-4f5b-6c7d-8e9f-0a1b2c3d4e5f")
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve and Check Log Evidence (Programmatic Signal)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        # Copy from Windows path defined in metadata or default
        result_path = metadata.get('result_path', "C:\\Users\\Public\\task_result.json")
        copy_from_env(result_path, temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        if result_data.get('log_evidence_found', False):
            score += 30
            feedback_parts.append("Log evidence confirmed: Tenant name found in logs.")
        else:
            feedback_parts.append("No log evidence found (configuration may not have been submitted).")
            
    except Exception as e:
        logger.warning(f"Failed to read task result from container: {e}")
        feedback_parts.append("Could not verify internal logs.")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. VLM Trajectory Verification (Visual Signal)
    # We sample frames to see the data entry process
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if not frames and not final_screen:
        return {"passed": False, "score": 0, "feedback": "No visual evidence available."}
        
    all_images = frames + ([final_screen] if final_screen else [])
    
    prompt = f"""
    You are verifying an IT Admin task in ManageEngine ADAudit Plus.
    
    GOAL: Configure Azure AD Auditing with these specific credentials:
    - Tenant Name: {expected_tenant}
    - Client ID: {expected_client_id}
    
    Analyze the screenshots to answer:
    1. Did the user navigate to 'Cloud Directory' or 'Configured Server(s)' or 'Add Tenant' screen?
    2. Is the Tenant Name '{expected_tenant}' visible in any input field?
    3. Is the Client ID '{expected_client_id}' visible in any input field?
    4. Did the user click a 'Save', 'Add', or 'Connect' button?
    5. Is there an error message about connection failure? (This is ACCEPTABLE and expected for fake credentials).
    
    Provide a score breakdown:
    - Navigation (20 pts)
    - Data Entry (Tenant Name & Client ID match) (30 pts)
    - Attempt to Save/Submit (20 pts)
    
    Return JSON:
    {{
        "navigation_score": 0-20,
        "data_entry_score": 0-30,
        "submission_score": 0-20,
        "evidence_found": ["list", "of", "findings"],
        "explanation": "Brief reasoning"
    }}
    """
    
    vlm_response = query_vlm(images=all_images, prompt=prompt)
    
    vlm_score = 0
    if vlm_response and 'parsed' in vlm_response:
        parsed = vlm_response['parsed']
        nav_score = parsed.get('navigation_score', 0)
        data_score = parsed.get('data_entry_score', 0)
        sub_score = parsed.get('submission_score', 0)
        
        vlm_score = nav_score + data_score + sub_score
        feedback_parts.append(f"Visual Verification: {parsed.get('explanation', 'No details')}")
        feedback_parts.append(f"Visual Evidence: {', '.join(parsed.get('evidence_found', []))}")
    else:
        feedback_parts.append("VLM analysis failed.")

    score += vlm_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }