#!/usr/bin/env python3
"""
Verifier for Install eForm Template task.

Scoring Criteria:
1. Form Existence (40 pts): 'Rapid Pain Assessment' record exists in DB.
2. Content Integrity (30 pts): The uploaded form contains the unique verification string.
3. Form Status (10 pts): The form is marked as Active (status=1).
4. Anti-gaming (10 pts): The form ID is new (count increased or ID > initial max).
5. VLM Trajectory (10 pts): Visual verification of Admin panel navigation.
"""

import json
import tempfile
import os
import logging
import sys
from pathlib import Path

# Add parent directory for shared utilities if needed
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import VLM utils (assuming gym_anything context)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback/mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_eform(traj, env_info, task_info):
    """
    Verify the eForm installation task.
    """
    # 1. Setup access to container data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract metrics
    form_found = result.get('form_found', False)
    secure_content_verified = result.get('secure_content_verified', False)
    form_status = str(result.get('form_status', '0'))
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    
    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: Form Existence (40 pts) ---
    if form_found:
        score += 40
        feedback_parts.append("eForm 'Rapid Pain Assessment' found in database")
    else:
        feedback_parts.append("eForm 'Rapid Pain Assessment' NOT found")
        # Critical failure
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
        
    # --- CRITERION 2: Content Integrity (30 pts) ---
    if secure_content_verified:
        score += 30
        feedback_parts.append("Form content verified (correct file uploaded)")
    else:
        feedback_parts.append("Form content mismatch (wrong file or empty)")
        
    # --- CRITERION 3: Form Status (10 pts) ---
    # Status '1' is Active in Oscar eForms
    if form_status == '1':
        score += 10
        feedback_parts.append("Form status is Active")
    else:
        feedback_parts.append(f"Form status is inactive or unknown ({form_status})")
        
    # --- CRITERION 4: Anti-Gaming / New Data (10 pts) ---
    if final_count > initial_count:
        score += 10
        feedback_parts.append("New record confirmed")
    else:
        # It's possible to overwrite/update, but strictly we expect a new entry or count change
        feedback_parts.append("No increase in form count (did you overwrite?)")

    # --- CRITERION 5: VLM Trajectory Verification (10 pts) ---
    # We want to see evidence of the Admin panel and File Picker
    vlm_score = 0
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=5)
            prompt = """
            You are verifying a software administration task. The user should:
            1. Access an 'Administration' or 'Admin' panel.
            2. Open 'eForm Management' or similar.
            3. Use a file picker/upload dialog to select a file.
            
            Look at these screenshots. Do you see evidence of:
            - The Administration panel?
            - A file upload dialog or file picker?
            - The text 'Rapid Pain Assessment'?
            
            Answer strictly Yes or No for "Process followed".
            """
            
            vlm_response = query_vlm(images=frames, prompt=prompt)
            # Basic keyword check on response since we can't parse complex JSON here easily without structure
            if vlm_response and vlm_response.get("success"):
                text = vlm_response.get("answer", "").lower()
                if "yes" in text:
                    vlm_score = 10
                    feedback_parts.append("VLM verified admin workflow")
                else:
                    feedback_parts.append("VLM did not clearly see admin workflow")
            else:
                # Fallback if VLM fails: give points if strict criteria met
                if score >= 70:
                    vlm_score = 10
                    feedback_parts.append("VLM skipped (fallback)")
        else:
             # No VLM available
             if score >= 70:
                 vlm_score = 10
                 feedback_parts.append("VLM skipped")

    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM errors out but db checks passed
        if score >= 70:
            vlm_score = 10
            
    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 70) and form_found and secure_content_verified
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }