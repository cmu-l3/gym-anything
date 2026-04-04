#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime, date

def verify_manage_adverse_drug_reaction(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Discontinued the Lisinopril medication (End Date set to Today).
    2. Added a new Allergy for Lisinopril (Date Today).
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

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

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    med_check = result.get('medication_check', {})
    allergy_check = result.get('allergy_check', {})
    
    today_str = date.today().strftime("%Y-%m-%d")

    # Criterion 1: Medication Discontinued (40 pts)
    # Check if end_date matches today
    med_end_date = med_check.get('end_date', '')
    if med_end_date and (med_end_date == today_str or med_end_date.startswith(today_str)):
        score += 40
        feedback.append("Success: Medication 'Lisinopril' was successfully discontinued (End Date set).")
    elif med_end_date:
        score += 20
        feedback.append(f"Partial: Medication end date set to {med_end_date}, expected {today_str}.")
    else:
        feedback.append("Fail: Medication 'Lisinopril' is still active (No End Date found).")

    # Criterion 2: Medication Comment (10 pts)
    # Check for "side effect" or reason
    # Note: The export script does a rough cut for comments, might be empty if column order varies, 
    # but we check existence.
    if med_check.get('comments'):
        score += 10
        feedback.append("Success: Discontinuation reason note added.")
    else:
        feedback.append("Note: No comment/reason found on medication discontinuation (Optional but recommended).")

    # Criterion 3: Allergy Added (40 pts)
    allergy_title = allergy_check.get('title', '')
    allergy_date = allergy_check.get('date', '')
    
    if allergy_title and ('lisinopril' in allergy_title.lower() or 'ace' in allergy_title.lower()):
        # Check date to ensure it wasn't pre-existing (setup script wiped them, so existence implies creation)
        if allergy_date and (allergy_date == today_str or allergy_date.startswith(today_str)):
            score += 40
            feedback.append("Success: New Allergy record for 'Lisinopril' created.")
        else:
            score += 30
            feedback.append("Partial: Allergy record found but date does not match today.")
    else:
        feedback.append("Fail: No new allergy record found for Lisinopril.")

    # Criterion 4: Allergy Reaction (10 pts)
    # We look for 'cough' in the reaction/diagnosis field captured
    # Note: In LibreHealth/OpenEMR 'diagnosis' column often holds the reaction text in some versions
    allergy_reaction = allergy_check.get('reaction', '').lower()
    if 'cough' in allergy_reaction:
        score += 10
        feedback.append("Success: Reaction 'Cough' documented correctly.")
    
    # 3. VLM Trajectory Verification (Optional but good for anti-gaming)
    # We want to verify they visited the "Allergies" section
    # This is implicit if the record exists, but good for robust scoring.
    # (Skipped for simple program verifier to keep it fast, relying on DB truth).

    # 4. Final Result
    passed = (score >= 80) # Must have done both main actions (40+40)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }