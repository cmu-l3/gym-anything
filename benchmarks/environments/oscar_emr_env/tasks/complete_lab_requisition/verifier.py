#!/usr/bin/env python3
"""
Verifier for complete_lab_requisition task.
"""

import json
import logging
import os
import tempfile
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_complete_lab_requisition(traj, env_info, task_info):
    """
    Verifies the lab requisition task using Database data and VLM.
    
    Criteria:
    1. Form Record Created (20 pts)
    2. Correct Tests Selected (40 pts - 10 each for Glucose, HbA1c, Lipid, Creatinine)
    3. Clinical Notes Correct (10 pts)
    4. VLM Workflow Verification (30 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load DB Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Database Verification ---
    form_found = result.get('form_found', 'false')
    form_data = result.get('form_data', {})
    
    if form_found == 'true':
        score += 20
        feedback.append("Lab requisition form created successfully.")
        
        # Check specific tests
        # Values from DB usually '1' for checked, '0' or empty for unchecked
        tests_map = {
            'glucose': ['1', 'true', 'on', 'checked'],
            'hba1c': ['1', 'true', 'on', 'checked'],
            'lipid': ['1', 'true', 'on', 'checked'],
            'creatinine': ['1', 'true', 'on', 'checked']
        }
        
        for test, valid_values in tests_map.items():
            val = str(form_data.get(test, '')).lower()
            if any(v in val for v in valid_values):
                score += 10
                feedback.append(f"Test '{test}' verified.")
            else:
                feedback.append(f"Test '{test}' MISSING or not selected.")

        # Check Notes
        notes = str(form_data.get('notes', '')).lower()
        required_keywords = task_info.get('metadata', {}).get('required_note_content', ['diabetes', 'fasting'])
        
        found_keywords = [k for k in required_keywords if k.lower() in notes]
        if len(found_keywords) >= 1:
            score += 10
            feedback.append(f"Clinical notes verified (found: {found_keywords}).")
        else:
            feedback.append("Clinical notes missing or insufficient.")
            
    elif form_found == 'true_generic':
        # Fallback if specific table wasn't populated but a form was created
        score += 20
        feedback.append("Form created, but specific content could not be programmatically verified (generic table fallback).")
        # Can't verify specific fields in this mode, rely on VLM
    else:
        feedback.append("No new lab requisition form found in database.")

    # --- VLM Verification ---
    # Sample frames to check workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    if all_frames:
        prompt = """
        Analyze these screenshots of a user using OSCAR EMR.
        The user goal is to create a Lab Requisition for patient Maria Santos.
        
        Look for:
        1. Patient Name "Maria Santos" or "Santos, Maria".
        2. A form titled "Ontario Lab Requisition" or similar.
        3. Checkboxes ticked for: Glucose/Fasting, HbA1c, Lipid Profile, Creatinine.
        4. Text entered in Clinical Information (mentioning Diabetes/Fasting).
        
        Did the user successfully navigate to the form and fill it out?
        """
        
        vlm_res = query_vlm(prompt=prompt, images=all_frames)
        
        if vlm_res.get('success'):
            vlm_content = vlm_res.get('parsed', {}) or vlm_res.get('raw', '')
            # Simple heuristic: if VLM is positive
            if "yes" in str(vlm_content).lower() or "successfully" in str(vlm_content).lower():
                score += 30
                feedback.append("VLM verification: Workflow looks correct.")
            else:
                # Partial credit if form found but VLM unsure
                if score > 20: 
                    score += 15
                    feedback.append("VLM verification: Ambiguous, but DB record exists.")
                else:
                    feedback.append("VLM verification: Workflow not clearly observed.")
        else:
            feedback.append("VLM verification failed to run.")
            if score >= 60: score += 10 # Grace points if DB is solid

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }