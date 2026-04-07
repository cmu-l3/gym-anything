#!/usr/bin/env python3
"""
Verifier for record_immunization task.

Scores out of 100 based on accurately recording a patient vaccination:
- 20 pts: New vaccination record exists
- 20 pts: Patient correctly identified (Ana Betz)
- 15 pts: Correct vaccine selected (Hepatitis B)
- 15 pts: Correct date (2025-01-15)
- 10 pts: Correct dose (2)
- 10 pts: Observations contain required occupational health info and lot number
- 10 pts: VLM Trajectory Verification
"""

import json
import logging
import os
import tempfile
import re

logger = logging.getLogger(__name__)


def verify_record_immunization(traj, env_info, task_info):
    """Verify vaccination record was created with accurate details."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('target_patient_firstname', 'Ana').lower()
    expected_lname = metadata.get('target_patient_lastname', 'Betz').lower()
    expected_vaccine = metadata.get('expected_vaccine', 'Hepatitis B').lower()
    expected_date = metadata.get('expected_date', '2025-01-15')
    expected_dose = metadata.get('expected_dose', 2)
    expected_lot = metadata.get('expected_lot', 'HBV-2025-0342').lower()
    expected_reason = metadata.get('expected_reason', 'workplace immunization program').lower()

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_immunization_result.json', local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}"
        }

    if result.get("error"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database export error: {result['error']}"
        }

    # 2. Score Database Entries
    new_record_found = result.get("new_record_found", False)
    record = result.get("record", {})

    if new_record_found and record:
        score += 20
        feedback_parts.append("New vaccination record created.")

        # Patient Match
        p_fname = record.get("patient_name", "").lower()
        p_lname = record.get("patient_lastname", "").lower()
        if expected_fname in p_fname and expected_lname in p_lname:
            score += 20
            feedback_parts.append("Patient correctly set to Ana Betz.")
        elif expected_fname in p_fname or expected_lname in p_lname:
            score += 10
            feedback_parts.append("Partial patient match (Check first/last name).")
        else:
            feedback_parts.append(f"Incorrect patient: {p_fname} {p_lname}.")

        # Vaccine Match
        vaccine_name = record.get("vaccine_name", "").lower()
        if expected_vaccine in vaccine_name:
            score += 15
            feedback_parts.append("Vaccine correctly set to Hepatitis B.")
        else:
            feedback_parts.append(f"Incorrect vaccine: {vaccine_name}.")

        # Date Match
        rec_date = record.get("date", "")
        if rec_date == expected_date:
            score += 15
            feedback_parts.append(f"Date correctly set to {expected_date}.")
        elif rec_date:
            feedback_parts.append(f"Incorrect date: {rec_date}.")
        else:
            feedback_parts.append("Date not set.")

        # Dose Match
        rec_dose = record.get("dose", -1)
        if rec_dose == expected_dose:
            score += 10
            feedback_parts.append("Dose correctly set to 2.")
        else:
            feedback_parts.append(f"Incorrect dose: {rec_dose}.")

        # Observations Match
        obs = record.get("observations", "").lower()
        lot_match = expected_lot in obs
        reason_match = expected_reason in obs
        
        if lot_match and reason_match:
            score += 10
            feedback_parts.append("Observations contain required lot number and justification.")
        elif lot_match or reason_match:
            score += 5
            feedback_parts.append("Observations partially correct (missing either lot number or justification).")
        else:
            feedback_parts.append("Observations missing required clinical/occupational context.")
            
    else:
        feedback_parts.append("FAIL: No new vaccination record was created.")

    # 3. Score VLM Trajectory (10 pts)
    # We use VLM to ensure the agent actually interacted with the UI rather than 
    # somehow directly inserting data (preventing gaming).
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Examine these screenshots from a GNU Health session.
            Did the user navigate to a Vaccination form, Immunization panel, or Patient health record to enter data?
            Look for UI elements like "Vaccinations", "Immunizations", "Health", "Dose", or "Medicament" in the application windows.
            Respond in JSON format: {"workflow_visible": true/false}
            """
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("parsed", {}).get("workflow_visible", False):
                score += 10
                feedback_parts.append("VLM verified correct UI workflow.")
            else:
                feedback_parts.append("VLM could not verify UI workflow (potential gaming or missing UI steps).")
    except Exception as e:
        logger.warning(f"VLM verification failed/unavailable: {e}")
        # If VLM is broken but DB is perfect, be lenient or stick to strict scoring.
        # We'll grant partial credit to avoid penalizing agent for framework issues if DB is completely correct.
        if score >= 80:
            score += 10
            feedback_parts.append("VLM unavailable, auto-granting UI workflow points due to perfect DB state.")

    passed = score >= 60 and new_record_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }