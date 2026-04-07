#!/usr/bin/env python3
"""
Verifier for schedule_patient_recall task.

Uses Database Verification to scan FreeMED's underlying MySQL tables.
Checks for:
1. Creation of a clinical record referencing "Colonoscopy"
2. Linkage to the correct patient ID (Thomas Vance)
3. Date math accuracy (Exactly 3 years in the future)
4. Inclusion of contextual clinical notes
"""

import json
import os
import tempfile
import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_patient_recall(traj, env_info, task_info):
    """
    Verify that a 3-year patient recall was scheduled for Thomas Vance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Calculate expected dates
    current_date = datetime.datetime.now()
    target_year = str(current_date.year + 3)
    target_month_str = f"{current_date.month:02d}"

    try:
        # Copy the database scan result from the container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            db_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported DB data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not db_data.get("success"):
        return {"passed": False, "score": 0, "feedback": f"Database scan failed: {db_data.get('error')}"}

    patient_id = db_data.get("patient_id")
    records = db_data.get("records", [])

    if not patient_id:
        return {"passed": False, "score": 0, "feedback": "Target patient Thomas Vance not found in database."}

    # Find candidate recall records
    # A candidate is any new record containing the word "colonoscopy"
    candidates = []
    for record in records:
        # Convert entire row to a single lowercase string for easy keyword searching
        row_str = " | ".join([str(v).lower() for v in record.values()])
        
        if "colonoscopy" in row_str:
            candidates.append((record, row_str))

    if not candidates:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new records found containing the procedure 'Colonoscopy'. Agent likely failed to save the recall."
        }

    # Evaluate the best candidate
    best_score = 0
    best_feedback = []
    
    for record, row_str in candidates:
        score = 30 # Base points for creating the record with the right procedure reason
        feedback_parts = ["Found record with 'Colonoscopy'"]

        # 1. Check Patient Linkage (30 points)
        # Verify the record is explicitly linked to Thomas Vance's ID
        if str(patient_id) in row_str:
            score += 30
            feedback_parts.append(f"Properly linked to Patient ID {patient_id}")
        else:
            feedback_parts.append(f"Record NOT linked to correct Patient ID {patient_id}")

        # 2. Check Date Math (30 points)
        # Expected date is 3 years in the future. We look for target year + month.
        if target_year in row_str and target_month_str in row_str:
            score += 30
            feedback_parts.append(f"Correct target date calculated ({target_year}-{target_month_str})")
        elif target_year in row_str:
            score += 15
            feedback_parts.append(f"Correct target year ({target_year}), but month unclear")
        else:
            feedback_parts.append(f"Incorrect future date. Expected year: {target_year}")

        # 3. Check Contextual Notes (10 points)
        if "polyp" in row_str or "follow-up" in row_str or "follow up" in row_str:
            score += 10
            feedback_parts.append("Contextual clinical notes included")
        else:
            feedback_parts.append("Missing required clinical notes")

        if score > best_score:
            best_score = score
            best_feedback = feedback_parts

    passed = best_score >= 60

    return {
        "passed": passed,
        "score": best_score,
        "feedback": " | ".join(best_feedback),
        "details": {
            "target_year_expected": target_year,
            "patient_id_expected": patient_id,
            "candidates_found": len(candidates)
        }
    }