#!/usr/bin/env python3
"""
Verifier for configure_chemical_safety_data task.

Verification Strategy:
1. VLM Verification (Primary): Analyze trajectory/final screenshot for correct NFPA/DOT values.
2. File Activity (Secondary): Confirm the CAMEO database file was modified.
3. App State (Sanity): Confirm CAMEO is running.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_chemical_safety_data(traj, env_info, task_info):
    """
    Verify that the chemical safety data was correctly entered.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_nfpa = {
        "health": metadata.get("nfpa_health", "2"),
        "flammability": metadata.get("nfpa_flammability", "3"),
        "instability": metadata.get("nfpa_instability", "0")
    }
    expected_dot = {
        "un": metadata.get("dot_un", "1114"),
        "class": metadata.get("dot_class", "3"),
        "pg": metadata.get("dot_pg", "II")
    }

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path inside container is C:\workspace\task_result.json
        # The copy_from_env usually handles path conversion or expects unix-style for the container shim.
        # Assuming standard mapping where /workspace in container view is accessible.
        # If the environment uses 'kubectl cp' style, we might need the exact path.
        # Based on env.json mounts: C:\workspace -> /workspace.
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Programmatic Checks
    score = 0
    feedback_parts = []
    
    # Check if DB was modified (20 pts)
    if result_data.get("db_modified", False):
        score += 20
        feedback_parts.append("Database file was saved.")
    else:
        feedback_parts.append("Database file NOT saved.")

    # Check if App is running (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("CAMEO is open.")
    else:
        feedback_parts.append("CAMEO is not running.")

    # 3. VLM Verification (70 pts)
    # We need to check if the specific values are visible in the screenshots
    
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
         return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    # Prompt designed to extract specific values
    prompt = f"""
    Analyze this screenshot of CAMEO Data Manager.
    
    I am looking for specific chemical safety data for 'Benzene'.
    
    1. Look for the NFPA 704 Diamond (Blue/Red/Yellow diamond shape or fields):
       - Health (Blue): Should be {expected_nfpa['health']}
       - Flammability (Red): Should be {expected_nfpa['flammability']}
       - Instability/Reactivity (Yellow): Should be {expected_nfpa['instability']}
       
    2. Look for DOT / Transportation fields:
       - UN Number: Should be {expected_dot['un']}
       - Hazard Class: Should be {expected_dot['class']}
       - Packing Group: Should be {expected_dot['pg']}
       
    Report specifically which values match.
    
    Format JSON:
    {{
        "chemical_name_visible": boolean,
        "nfpa_health_match": boolean,
        "nfpa_flammability_match": boolean,
        "nfpa_instability_match": boolean,
        "dot_un_match": boolean,
        "dot_class_match": boolean,
        "dot_pg_match": boolean
    }}
    """

    vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
    
    if vlm_response.get("success"):
        vlm_data = vlm_response.get("parsed", {})
        
        # Scoring logic
        if vlm_data.get("chemical_name_visible"):
            score += 10
        
        if vlm_data.get("nfpa_health_match"): score += 10
        if vlm_data.get("nfpa_flammability_match"): score += 10
        if vlm_data.get("nfpa_instability_match"): score += 10
        
        if vlm_data.get("dot_un_match"): score += 10
        if vlm_data.get("dot_class_match"): score += 10
        if vlm_data.get("dot_pg_match"): score += 10
        
        feedback_parts.append(f"VLM Analysis: {json.dumps(vlm_data)}")
    else:
        feedback_parts.append("VLM verification failed to process image.")

    passed = score >= 90  # Strict threshold for safety data
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }