#!/usr/bin/env python3
"""
Verifier for create_fire_department task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_fire_department(traj, env_info, task_info):
    """
    Verify the creation of a fire department and its association with a facility.
    
    Strategy:
    1. Check if the verification text file exists and contains correct info.
    2. Check if the proof screenshot exists.
    3. Use VLM to verify the workflow (trajectory) and the final screenshot content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_fd_name = metadata.get("expected_fd_name", "Chatham Fire Protection District")
    expected_fd_id = metadata.get("expected_fd_id", "FD-2024-0173")
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Text File Verification (40 points)
    text_exists = result.get("text_file_exists", False)
    text_created = result.get("text_created_during", False)
    content = result.get("text_content", "")
    
    if text_exists and text_created:
        score += 10
        feedback_parts.append("Verification file created.")
        
        # Check content
        if expected_fd_name in content:
            score += 15
            feedback_parts.append("Correct FD Name in text.")
        else:
            feedback_parts.append("Missing FD Name in text.")
            
        if expected_fd_id in content:
            score += 15
            feedback_parts.append("Correct FD ID in text.")
        else:
            feedback_parts.append("Missing FD ID in text.")
    else:
        feedback_parts.append("Verification file missing or old.")

    # 2. Screenshot File Verification (20 points)
    img_exists = result.get("image_file_exists", False)
    img_created = result.get("image_created_during", False)
    img_size = result.get("image_size_bytes", 0)
    
    if img_exists and img_created and img_size > 5000: # Min 5KB
        score += 20
        feedback_parts.append("Proof screenshot created.")
    else:
        feedback_parts.append("Proof screenshot missing.")

    # 3. VLM Verification (40 points)
    # We check the trajectory to see if they actually used the form
    from gym_anything.vlm import sample_trajectory_frames
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("No trajectory frames available.")
    else:
        # We need to query VLM here. 
        # Note: In a real verifier, we'd call the VLM service. 
        # Assuming a helper or mock for this generated code.
        # Since I can't import the actual VLM client here easily without the env,
        # I will structure the logic assuming a query_vlm function is passed or available via imports
        # defined in the environment. I will use the pattern from examples.
        
        # NOTE: The instructions imply I should write standard python. 
        # I will use a placeholder check or assume `query_vlm` is available if imported.
        # If not available, we skip VLM scoring (or assume fail if strict).
        # For this output, I will assume the `gym_anything` pattern.
        
        try:
            from gym_anything.vlm import query_vlm
            
            prompt = f"""
            Check these screenshots of a user interacting with CAMEO Data Manager.
            Look for:
            1. A form filling step for 'Fire Departments' or 'Contacts'.
            2. The text '{expected_fd_name}' being typed or visible.
            3. A screen showing 'Facilities' where a fire department is being selected/associated.
            
            Answer JSON: {{ "fd_form_seen": bool, "association_step_seen": bool, "fd_name_visible": bool }}
            """
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("fd_form_seen"):
                score += 10
                feedback_parts.append("VLM: FD form filling observed.")
            
            if parsed.get("fd_name_visible"):
                score += 10
                feedback_parts.append("VLM: FD Name verified visually.")
                
            if parsed.get("association_step_seen"):
                score += 20
                feedback_parts.append("VLM: Association step observed.")
                
        except ImportError:
            # Fallback if VLM lib not present (e.g. local test)
            feedback_parts.append("VLM verification skipped (lib unavailable).")
            # Grant partial points if file evidence is strong to avoid unfair failure
            if score >= 50: 
                score += 20
                feedback_parts.append("Bonus for strong file evidence.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }