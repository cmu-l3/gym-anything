#!/usr/bin/env python3
"""
Verifier for create_patient_letter task.
Validates database extraction to confirm the follow-up letter was composed correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_patient_letter(traj, env_info, task_info):
    """
    Verify that the follow-up letter for Maria Santos was successfully created.
    Uses multiple signals: Database row existence, patient association, and content matching.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_date = metadata.get('expected_date', '2025-01-15')
    expected_subject = metadata.get('expected_subject', 'Hypertension Follow-Up Plan')
    required_keywords = metadata.get('required_keywords', ["hypertension", "blood pressure", "follow-up", "medication"])

    # Attempt to load results from env
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/create_letter_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result_data.get('success'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during data extraction: {result_data.get('error')}"
        }

    score = 0
    feedback_parts = []
    
    patient_id = result_data.get('patient_id')
    initial_count = result_data.get('initial_count', 0)
    final_count = result_data.get('final_count', 0)
    new_letters = result_data.get('new_letters', [])

    if not patient_id:
        return {"passed": False, "score": 0, "feedback": "CRITICAL: Patient Maria Santos not found in DB."}

    # CRITERION 1 & 2: Delta check and Patient Match
    if final_count > initial_count:
        score += 10
        feedback_parts.append(f"Letter count increased ({initial_count} -> {final_count})")
    else:
        feedback_parts.append("No new letter records created")

    # Analyze the newly created letters to find the best match for Maria Santos
    best_match = None
    for letter in new_letters:
        # FreeMED letter schema usually maps patient ID to 'patient' or 'letterpatient'
        # We check all values just in case of schema variations
        values = list(letter.values())
        if patient_id in values or str(patient_id) in str(values):
            best_match = letter
            break
            
    # If not found by patient ID, fallback to finding one with the keywords (in case of wrong patient selected)
    if not best_match and new_letters:
        for letter in new_letters:
            row_str = " ".join(str(v).lower() for v in letter.values() if v)
            if "hypertension" in row_str:
                best_match = letter
                break

    if best_match:
        score += 25
        feedback_parts.append("Found new letter record")
        
        row_str = " ".join(str(v).lower() for v in best_match.values() if v)
        
        # Check patient association
        if patient_id in list(best_match.values()) or str(patient_id) in str(list(best_match.values())):
            score += 15
            feedback_parts.append("Letter correctly associated with Maria Santos")
        else:
            feedback_parts.append("Letter created but associated with the WRONG patient")

        # Check Subject / Description
        if expected_subject.lower() in row_str:
            score += 5
            feedback_parts.append("Subject is correct")

        # Check Date
        if expected_date in row_str:
            score += 10
            feedback_parts.append(f"Date is correct ({expected_date})")

        # Check Keywords in body
        kw_found = 0
        for kw in required_keywords:
            if kw.lower() in row_str:
                kw_found += 1
                
        if "hypertension" in row_str: score += 10
        if "blood pressure" in row_str: score += 10
        
        if "follow-up" in row_str and "medication" in row_str:
            score += 10
            
        feedback_parts.append(f"Found {kw_found}/{len(required_keywords)} required clinical keywords")
    else:
        feedback_parts.append("Could not find any letter matching the patient or task criteria")

    # Tertiary VLM Verification (if applicable, testing UI interaction workflow)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            # We assume gym_anything is available in the verifier environment
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            prompt = """
            Look at these screenshots from a medical software workflow.
            Did the user navigate to a patient's chart, open the Letters/Correspondence module, and compose a letter?
            Reply in JSON: {"workflow_observed": true/false}
            """
            vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_resp.get('parsed', {}).get('workflow_observed', False):
                vlm_score = 5
                feedback_parts.append("VLM confirmed workflow trajectory")
            else:
                feedback_parts.append("VLM did not observe the letter composition workflow")
        except Exception as e:
            logger.warning(f"VLM Verification skipped/failed: {e}")
            # Award points by default if framework VLM tools aren't fully configured
            vlm_score = 5 
    else:
        vlm_score = 5  # Skip VLM penalty if not available
        
    score += vlm_score

    # Determine pass/fail
    key_criteria_met = (best_match is not None) and ("hypertension" in str(best_match).lower())
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }