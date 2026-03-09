#!/usr/bin/env python3
"""
Verifier for record_disposition task.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_disposition(traj, env_info, task_info):
    """
    Verifies that the agent recorded an 'Admit Patient' disposition with the correct note.
    """
    # 1. Setup Result Reading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure Error: copy_from_env missing"}

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

    # 2. Extract Data
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    encounter_found = result.get('encounter_found', False)
    disposition_value = result.get('disposition_value', "")
    disposition_note = result.get('disposition_note', "")
    
    score = 0
    feedback = []
    
    # 3. Scoring Logic
    
    # Criterion 1: New Encounter Created (Anti-Gaming) (20 pts)
    if current_count > initial_count:
        score += 20
        feedback.append("Success: New encounter created.")
    else:
        feedback.append("Fail: No new encounter count increase detected.")

    # Criterion 2: Disposition Recorded as 'Admit' (40 pts)
    if encounter_found and disposition_value and "admit" in disposition_value.lower():
        score += 40
        feedback.append(f"Success: Disposition '{disposition_value}' recorded.")
    else:
        feedback.append(f"Fail: Expected 'Admit Patient', found '{disposition_value}'.")

    # Criterion 3: Note Content (20 pts)
    # Keywords: pneumonia, SpO2, antibiotics
    required_keywords = ["pneumonia", "spo2", "antibiotics"]
    found_keywords = [k for k in required_keywords if k in str(disposition_note).lower()]
    
    if len(found_keywords) >= 2:
        score += 20
        feedback.append(f"Success: Note contains required clinical details ({len(found_keywords)} matches).")
    elif disposition_note:
        score += 10
        feedback.append("Partial: Note exists but missing key clinical details.")
    else:
        feedback.append("Fail: No disposition note found.")

    # Criterion 4: VLM Verification (20 pts)
    # Check if we can see the "Disposition" tab or the success message in the trajectory
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a medical software interface (Bahmni).
        I am looking for evidence that the user:
        1. Selected the 'Disposition' tab/button.
        2. Selected 'Admit Patient' (or 'Admit').
        3. Typed a note about pneumonia.
        
        Do you see any of these actions or the final saved state showing 'Admit Patient'?
        Answer 'YES' or 'NO' and explain.
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_resp.get('success') and "YES" in vlm_resp.get('parsed', {}).get('answer', '').upper():
                vlm_score = 20
                feedback.append("Success: Visual verification confirmed workflow.")
            elif vlm_resp.get('success'):
                # Soft fail on VLM if API verified it, but still check
                feedback.append("Info: VLM did not clearly see the actions (this is common if steps were fast).")
        except Exception:
            feedback.append("Info: VLM verification skipped due to error.")
    
    score += vlm_score

    # 4. Final Result
    # Pass if score >= 60 AND API verification passed (Criterion 2 is critical)
    passed = (score >= 60) and (encounter_found is True) and ("admit" in str(disposition_value).lower())

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }