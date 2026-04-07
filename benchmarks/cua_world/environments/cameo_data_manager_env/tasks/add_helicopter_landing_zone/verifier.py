#!/usr/bin/env python3
"""
Verifier for add_helicopter_landing_zone task.

Verification Strategy:
1. Anti-Gaming: Check if the CAMEO database file was actually modified during the task.
   (Ensures the agent didn't just type text into a notepad).
2. VLM Verification: Use the final screenshot (and trajectory if available) to verify:
   - The user is in the "Resources" module.
   - A record named "LZ North Complex" is visible.
   - The Notes field contains critical safety keywords ("light poles", "Grass", "123.450").

Scoring:
- Database Modified: 20 pts
- VLM confirmation of Record Name: 30 pts
- VLM confirmation of Safety Notes: 50 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_helicopter_landing_zone(traj, env_info, task_info):
    """
    Verifies the Helicopter LZ task using Database timestamps and VLM visual confirmation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # The export script saves to C:\tmp\task_result.json, which maps to /tmp/task_result.json 
        # inside the container context usually, but for Windows containers accessing via copy_from_env
        # we often use the absolute path in the container.
        # Assuming copy_from_env handles the path mapping or we use the windows path.
        # Try standard temp path first.
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Anti-Gaming: DB Modification Check (20 pts)
    if result_data.get("db_file_modified", False):
        score += 20
        feedback_parts.append("Database file updated successfully.")
    else:
        feedback_parts.append("Warning: Database file was not modified. Did you save the record?")

    # 3. VLM Verification (80 pts)
    # We use the final screenshot captured by the framework (or the export script)
    # The framework's get_final_screenshot(traj) is preferred.
    final_img = get_final_screenshot(traj)
    
    if not final_img:
        # Fallback to the one exported by script if framework one is missing
        # But for this verifier, we assume framework handles image passing
        return {"passed": False, "score": score, "feedback": "No visual evidence (screenshot) available."}

    # Construct Prompt
    metadata = task_info.get('metadata', {})
    required_notes = metadata.get('required_strings_in_notes', [])
    resource_name = metadata.get('resource_name', "LZ North Complex")
    
    prompt = f"""
    You are verifying an agent's work in CAMEO Data Manager.
    
    Goal: The agent should have created a Resource record for a Helicopter Landing Zone.
    
    Please examine the screenshot and answer:
    1. Is the "Resources" module or a Resource Detail view visible?
    2. Is the Name "LZ North Complex" visible?
    3. Do you see the Notes/Comments field containing the following safety info?
       - "Grass" or "Clay"
       - "200x200"
       - "light poles"
       - "123.450"
       
    Return JSON:
    {{
        "resource_module_visible": true/false,
        "name_match": true/false,
        "safety_notes_match": true/false,
        "missing_info": "list of missing items"
    }}
    """
    
    vlm_response = query_vlm(
        prompt=prompt,
        image=final_img
    )
    
    if vlm_response.get('success'):
        parsed = vlm_response.get('parsed', {})
        
        # Name Match (30 pts)
        if parsed.get('name_match'):
            score += 30
            feedback_parts.append(f"Resource '{resource_name}' found.")
        else:
            feedback_parts.append(f"Could not find resource name '{resource_name}' in screenshot.")
            
        # Notes Match (50 pts)
        if parsed.get('safety_notes_match'):
            score += 50
            feedback_parts.append("Safety notes verified correct.")
        elif parsed.get('resource_module_visible'):
            # Partial credit if they are in the right place but notes are obscure
            score += 10
            feedback_parts.append("In Resources module, but safety notes incomplete or not visible.")
    else:
        feedback_parts.append("VLM verification failed to process image.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }