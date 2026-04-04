#!/usr/bin/env python3
"""
Verifier for document_past_surgical_history task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_past_surgical_history(traj, env_info, task_info):
    """
    Verify that the agent added the correct past surgical history.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('procedure_name', 'Laparoscopic Appendectomy').lower()
    expected_date_str = metadata.get('procedure_date', '2019-06-15')
    expected_notes_snippet = "St. Mary's".lower()

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    procedures = result.get('procedures', [])
    patient_id = result.get('patient_id', 'unknown')

    if not procedures:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"No procedure documents found for patient {patient_id}. Did you save the record?"
        }

    # Find the best matching procedure
    best_score = 0
    best_feedback = []
    
    for proc in procedures:
        current_score = 0
        current_feedback = []
        
        # 1. Procedure Name (Max 30)
        p_name = proc.get('procedure_name', '').lower()
        if 'appendectomy' in p_name:
            current_score += 30
            current_feedback.append("Procedure name correct.")
        elif p_name:
            current_score += 5
            current_feedback.append(f"Procedure name mismatch: found '{p_name}'.")
        else:
            current_feedback.append("Procedure name missing.")

        # 2. Date (Max 40) - CRITICAL: Must be 2019
        p_date = proc.get('date', '')
        # Handle various formats: timestamp (int), ISO string, simple string
        date_correct = False
        
        # Check simple string match
        if expected_date_str in str(p_date):
            date_correct = True
        
        # Check timestamp (approximate)
        # 2019-06-15 is approx 1560556800000 ms
        try:
            ts = int(str(p_date))
            # Check if it's ms or sec
            if ts > 2000000000: # ms
                ts = ts / 1000
            
            # Check if year is 2019
            dt = datetime.fromtimestamp(ts)
            if dt.year == 2019 and dt.month == 6:
                date_correct = True
        except:
            pass
            
        # Check substring for year/month
        if '2019' in str(p_date) and ('06' in str(p_date) or '6' in str(p_date)):
            date_correct = True
            
        if date_correct:
            current_score += 40
            current_feedback.append("Date correct (June 2019).")
        else:
            # Check if they used today's date (common error)
            current_feedback.append(f"Date mismatch: found '{p_date}', expected '2019-06-15'.")

        # 3. Notes (Max 30)
        p_notes = proc.get('notes', '').lower()
        if expected_notes_snippet in p_notes:
            current_score += 30
            current_feedback.append("Notes correct.")
        elif p_notes:
            current_score += 10
            current_feedback.append("Notes present but missing 'St. Mary's'.")
        else:
            current_feedback.append("Notes missing.")

        if current_score > best_score:
            best_score = current_score
            best_feedback = current_feedback

    passed = best_score >= 80  # Requires decent accuracy
    
    return {
        "passed": passed,
        "score": best_score,
        "feedback": " ".join(best_feedback)
    }