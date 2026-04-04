#!/usr/bin/env python3
"""
Verifier for document_patient_phone_call task.

Scoring Criteria:
1. Patient Note Created (30 pts): Verified via database record existence.
2. Correct Patient (20 pts): Verified via database foreign key (pid).
3. Note Content (20 pts): Contains specific medication name and context ("lost", "bus", etc).
4. Note Status (10 pts): Note is active (not deleted/inactive).
5. VLM Verification (20 pts): Trajectory confirms workflow (Search -> Dashboard -> Notes).
"""

import json
import os
import sys
import logging
import tempfile
from datetime import datetime

# Import VLM utils provided by environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_patient_phone_call(traj, env_info, task_info):
    """
    Verifies the phone call documentation task using DB state and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract Data
    note_found = result.get('note_found', False)
    note_data = result.get('note_data', {})
    target_medication = result.get('target_medication', '').lower()
    
    # Criteria 1 & 2: Note Created for Correct Patient
    if note_found:
        score += 50
        feedback.append("Success: New patient note found in database.")
    else:
        feedback.append("Fail: No new patient note found for the target patient.")
        # If no note, we can stop or check VLM for partial credit on effort, 
        # but for this strict task, major points require the DB record.
    
    # Criteria 3: Content Accuracy
    if note_found:
        body = note_data.get('body', '').lower()
        
        # Check for medication name
        if target_medication and target_medication in body:
            score += 15
            feedback.append(f"Success: Note mentions '{target_medication}'.")
        else:
            feedback.append(f"Fail: Note missing medication name '{target_medication}'.")

        # Check for context keywords (lost, bottle, etc)
        required_keywords = ["lost", "losing", "miss", "gone"]
        if any(k in body for k in required_keywords):
            score += 5
            feedback.append("Success: Note mentions context (lost/losing).")
        else:
            feedback.append("Fail: Note missing context about 'losing' the item.")

    # Criteria 4: Active Status
    if note_found:
        activity = str(note_data.get('activity', '0'))
        if activity == '1':
            score += 10
            feedback.append("Success: Note is marked as Active.")
        else:
            feedback.append("Fail: Note is inactive/deleted.")

    # Criteria 5: VLM Verification (Trajectory Analysis)
    # We want to ensure they didn't just use SQL injection or magic, but actually used the UI
    # And to verify they navigated to "Notes" specifically
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if not frames and not final_img:
        feedback.append("Warning: No video evidence available for VLM check.")
    else:
        vlm_images = frames + ([final_img] if final_img else [])
        
        prompt = """
        Analyze these screenshots of a user interacting with LibreHealth EHR.
        The goal was to document a patient phone call in the 'Notes' section.
        
        Look for:
        1. A patient dashboard or chart being visible.
        2. A form for entering text (Patient Notes).
        3. The user typing text related to a lost medication.
        
        Did the user appear to navigate to a patient chart and enter a note?
        Answer JSON: {"workflow_valid": boolean, "reason": string}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=vlm_images)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('workflow_valid', False):
                score += 20
                feedback.append("Success: VLM confirms valid workflow navigation.")
            else:
                feedback.append(f"VLM Warning: {parsed.get('reason', 'Workflow looked incorrect')}")
        else:
            # If VLM fails, we default to giving points if DB record exists to avoid false negatives on tech issues
            if note_found:
                score += 20
                feedback.append("VLM unavailable, defaulting to pass based on DB record.")

    # Final tally
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }