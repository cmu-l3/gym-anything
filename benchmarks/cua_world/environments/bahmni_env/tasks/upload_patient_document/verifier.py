#!/usr/bin/env python3
"""
Verifier for upload_patient_document task.

Criteria:
1. An observation exists for the correct patient (Maria Gonzalez).
2. The observation was created during the task window (checked via export script logic).
3. The observation represents the uploaded file 'external_lab_report.jpg'.
4. VLM Verification: Verify file picker interaction from trajectory (optional but good context).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_patient_document(traj, env_info, task_info):
    """
    Verify that the file was uploaded to the correct patient.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Programmatic Checks ---
    
    # Criterion 1: Observation Found (30 pts)
    obs_found = result.get('observation_found', False)
    target_uuid = result.get('target_patient_uuid', '')
    
    if not target_uuid:
         return {"passed": False, "score": 0, "feedback": "Setup failed: Target patient not identified"}

    if obs_found:
        score += 30
        feedback_parts.append("New observation found on patient record")
    else:
        feedback_parts.append("No new document observation found for Maria Gonzalez")
        
    # Criterion 2: Filename Match (40 pts)
    filename_match = result.get('filename_match', False)
    obs_value = result.get('observation_value', '')
    
    if filename_match:
        score += 40
        feedback_parts.append("Uploaded filename matches 'external_lab_report'")
    elif obs_found:
        feedback_parts.append(f"Observation found but filename mismatch (Value: {obs_value})")

    # --- VLM Verification (30 pts) ---
    # We want to see if the agent actually used the file picker mechanism
    
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=8)
        
        prompt = """
        Review this sequence of screenshots from a medical software task.
        The goal was to upload a file named 'external_lab_report.jpg'.
        
        Look for:
        1. A system file picker dialog (window title 'Open' or 'Select File').
        2. Selection of the file 'external_lab_report.jpg' or 'external_lab_report'.
        3. A dashboard showing 'Maria Gonzalez'.
        
        Answer these questions:
        - Did the agent open a file picker dialog? (yes/no)
        - Is there visual evidence of selecting the correct file? (yes/no)
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get('parsed', {}) if 'parsed' in vlm_resp else {}
            # Fallback simple parsing if structured parsing isn't guaranteed
            resp_text = vlm_resp.get('response', '').lower()
            
            picker_seen = 'yes' in resp_text and ('picker' in resp_text or 'dialog' in resp_text)
            
            if picker_seen or "system file picker" in resp_text:
                vlm_score += 15
                feedback_parts.append("VLM confirmed file picker usage")
            
            # If we missed programmatic confirmation but VLM sees success, give partial credit
            # But normally programmatic is king here.
            
            # Give full VLM points if programmatic success is 100% (implicit pass)
            if score >= 70:
                vlm_score = 30
            else:
                # If partial programmatic, VLM adds context
                if vlm_score > 0:
                     vlm_score += 15 # Boost if picker was at least opened
                     
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If programmatic passed, don't penalize for VLM failure
            if score >= 70:
                vlm_score = 30
    else:
        # No VLM available; if programmatic passed, assume full points
        if score >= 70:
            vlm_score = 30
            
    score += vlm_score

    # Final Pass Determination
    passed = score >= 70 and obs_found and filename_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }