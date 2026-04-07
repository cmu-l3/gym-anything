#!/usr/bin/env python3
import json
import os
import base64
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_patient_form_template(traj, env_info, task_info):
    """
    Verifies the creation of the COVID-19 Screening form.
    
    Strategy:
    1. Check if the string "COVID-19 Screening" exists in the database dump (via export_result.sh).
    2. Check if the context around that string contains the required fields (Fever, Cough, Travel).
    3. Use VLM to verify the UI interaction (Form Builder usage).
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Database Verification (40 points)
    score = 0
    feedback = []
    
    form_found = result.get('form_found', False)
    if form_found:
        score += 40
        feedback.append("Database: 'COVID-19 Screening' form record found.")
    else:
        feedback.append("Database: Form title not found in database.")

    # 3. Field Verification (30 points)
    # We analyze the context (SQL dump snippet) for field labels
    context_b64 = result.get('form_context_base64', "")
    fields_found = 0
    required_fields = ["fever", "cough", "travel"]
    
    if context_b64:
        try:
            context_str = base64.b64decode(context_b64).decode('utf-8', errors='ignore').lower()
            
            for field in required_fields:
                if field in context_str:
                    fields_found += 1
                    feedback.append(f"Database: Found field '{field}' in form definition.")
                else:
                    feedback.append(f"Database: Missing field '{field}'.")
                    
            if fields_found >= 3:
                score += 30
            else:
                score += (fields_found * 10)
                
        except Exception as e:
            feedback.append(f"Error decoding DB context: {e}")

    # 4. VLM Verification (30 points)
    # Check if the user actually used the form builder UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from an EHR system (NOSH).
    The user is supposed to:
    1. Navigate to Administration/Settings -> Forms.
    2. Create a new form titled 'COVID-19 Screening'.
    3. Add fields for 'Fever', 'Cough', and 'Travel History'.
    4. Save the form.

    Answer YES or NO to:
    A) Did the user access a Form Builder or Template creation screen?
    B) Is the title 'COVID-19 Screening' visible in input fields or lists?
    C) Are the specific questions (Fever/Cough/Travel) visible?
    """
    
    try:
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        feedback.append(f"VLM Analysis: {vlm_response.get('response', 'No response')}")
        
        # Simple keyword matching on VLM response
        vlm_text = str(vlm_response).lower()
        
        vlm_score = 0
        if "builder" in vlm_text or "template" in vlm_text:
            vlm_score += 10
        if "covid" in vlm_text:
            vlm_score += 10
        if "fever" in vlm_text or "cough" in vlm_text:
            vlm_score += 10
            
        score += vlm_score
        
    except Exception as e:
        feedback.append(f"VLM check failed: {e}")
        # Graceful degradation: if VLM fails but DB confirmed everything, give full points
        if form_found and fields_found >= 3:
            score += 30

    # 5. Final Decision
    # Pass if Form exists (40) + At least 2 fields found (20) = 60 points
    passed = (score >= 60) and form_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }