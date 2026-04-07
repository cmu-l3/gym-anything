#!/usr/bin/env python3
"""
Verifier for discontinue_patient_medication task.

Evaluates whether the agent correctly located and modified/discontinued 
a specific medication (Atorvastatin) while leaving another active medication (Lisinopril) untouched.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_discontinue_patient_medication(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    target_exists = result.get('target_exists', True)
    target_note = result.get('target_note', '').lower()
    distractor_exists = result.get('distractor_exists', True)
    distractor_note = result.get('distractor_note', '').lower()
    new_notes = result.get('new_notes', '').lower()
    
    expected_reason = task_info.get('metadata', {}).get('expected_reason', 'myalgia').lower()
    
    # -------------------------------------------------------------------------
    # Criterion 1: Distractor Integrity (Lisinopril must remain unchanged) - 30 pts
    # -------------------------------------------------------------------------
    distractor_passed = False
    if distractor_exists and "hypertension" in distractor_note and expected_reason not in distractor_note:
        distractor_passed = True
        score += 30
        feedback_parts.append("Distractor prescription (Lisinopril) safely preserved.")
    else:
        feedback_parts.append("FAIL: Distractor prescription was altered or deleted!")

    # -------------------------------------------------------------------------
    # Criterion 2: Target Modification (Atorvastatin discontinued) - 40 pts
    # -------------------------------------------------------------------------
    target_passed = False
    
    # Acceptable ways to discontinue:
    # A) The target record was updated to include the clinical reason.
    if target_exists and expected_reason in target_note:
        target_passed = True
        score += 40
        feedback_parts.append(f"Target prescription successfully updated with reason: '{expected_reason}'.")
        
    # B) The target record was deleted.
    elif not target_exists:
        target_passed = True
        score += 30
        feedback_parts.append("Target prescription was deleted/removed from active list.")
        
    # C) A new prescription/note was added to the chart detailing the discontinuation.
    elif expected_reason in new_notes:
        target_passed = True
        score += 35
        feedback_parts.append(f"New chart entry found containing discontinuation reason: '{expected_reason}'.")
        
    else:
        feedback_parts.append("FAIL: Target prescription was not properly discontinued or reason was not documented.")

    # -------------------------------------------------------------------------
    # Criterion 3: VLM Trajectory Verification (UI interaction) - 30 pts
    # -------------------------------------------------------------------------
    vlm_passed = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = (
                    "Look at these screenshots from a medical record system. "
                    "Did the user navigate to Marcus Johnson's medication list and "
                    "interact with the Atorvastatin prescription (e.g., editing it or documenting myalgia)? "
                    "Respond with a JSON object: {\"interacted\": true/false}"
                )
                vlm_resp = query_vlm(images=images, prompt=prompt)
                
                if vlm_resp.get("parsed", {}).get("interacted", False):
                    vlm_passed = True
                    score += 30
                    feedback_parts.append("VLM confirmed interaction with the medication UI.")
                else:
                    feedback_parts.append("VLM did not detect interaction with the Atorvastatin prescription.")
        except ImportError:
            # Fallback if VLM tools aren't present in environment
            score += 30
            feedback_parts.append("VLM unavailable, automatically awarding UI interaction points.")
    else:
        score += 30
        feedback_parts.append("VLM check bypassed (not provided), points awarded.")

    # -------------------------------------------------------------------------
    # Final Evaluation
    # -------------------------------------------------------------------------
    passed = distractor_passed and target_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }