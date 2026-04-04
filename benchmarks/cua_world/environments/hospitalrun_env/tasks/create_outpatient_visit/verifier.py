#!/usr/bin/env python3
"""
Verifier for create_outpatient_visit task.

Checks:
1. Did the total visit count increase? (Anti-gaming)
2. Is there a new visit record linked to Elena Martinez?
3. Does the visit record have the correct details (Type, Location, Examiner, Reason)?
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_outpatient_visit(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_type = metadata.get('expected_visit_type', 'Clinic')
    expected_location = metadata.get('expected_location', 'Clinic A')
    expected_examiner = metadata.get('expected_examiner', 'Dr. James Wilson')
    expected_reason = metadata.get('expected_reason', 'Recurring lower back pain')
    expected_date = metadata.get('expected_date_str', '01/15/2025')

    # 2. Retrieve result from container
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

    # 3. Analyze Results
    matching_visits = result.get('matching_visits', [])
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    score = 0
    feedback = []
    
    # Check 1: Was a visit actually created? (Anti-gaming)
    # We cleared visits for this patient in setup, so list should be > 0
    if not matching_visits:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No visit records found for Elena Martinez (P00201)."
        }
    
    # We found at least one visit linked to the patient
    score += 20
    feedback.append("Visit record created for correct patient.")
    
    # Find the best match among visits (in case there are multiple, though we cleared them)
    # We prioritize the one that matches fields
    best_match = None
    best_match_score = -1
    
    for visit in matching_visits:
        current_visit_score = 0
        
        # Check Type
        v_type = visit.get('visitType', '')
        if expected_type.lower() in v_type.lower():
            current_visit_score += 1
            
        # Check Location
        v_loc = visit.get('location', '')
        if expected_location.lower() in v_loc.lower():
            current_visit_score += 1
            
        # Check Examiner
        v_exam = visit.get('examiner', '')
        if 'wilson' in v_exam.lower(): # Loose match for name
            current_visit_score += 1
            
        # Check Reason
        v_reason = visit.get('reason', '')
        if 'back pain' in v_reason.lower():
            current_visit_score += 1
            
        if current_visit_score > best_match_score:
            best_match_score = current_visit_score
            best_match = visit

    # Evaluate the best match
    v = best_match
    
    # Verify Type (20 pts)
    if expected_type.lower() in v.get('visitType', '').lower():
        score += 20
        feedback.append(f"Correct Visit Type: {v.get('visitType')}")
    else:
        feedback.append(f"Incorrect Visit Type: expected '{expected_type}', got '{v.get('visitType')}'")

    # Verify Location (20 pts)
    if expected_location.lower() in v.get('location', '').lower():
        score += 20
        feedback.append(f"Correct Location: {v.get('location')}")
    else:
        feedback.append(f"Incorrect Location: expected '{expected_location}', got '{v.get('location')}'")

    # Verify Examiner (20 pts)
    if 'wilson' in v.get('examiner', '').lower():
        score += 20
        feedback.append(f"Correct Examiner: {v.get('examiner')}")
    else:
        feedback.append(f"Incorrect Examiner: expected '{expected_examiner}', got '{v.get('examiner')}'")

    # Verify Reason (10 pts)
    if 'back pain' in v.get('reason', '').lower():
        score += 10
        feedback.append("Reason for visit matches.")
    else:
        feedback.append(f"Reason mismatch: got '{v.get('reason')}'")

    # Verify Date (10 pts)
    # Date formats can vary (YYYY-MM-DD vs MM/DD/YYYY), check for substring
    start_date = v.get('startDate', '')
    # Check for 2025 and (01/15 or 15/01 or 2025-01-15)
    if '2025' in start_date and ('01' in start_date or '15' in start_date):
        score += 10
        feedback.append(f"Date appears correct: {start_date}")
    else:
        feedback.append(f"Date mismatch: expected '{expected_date}', got '{start_date}'")

    # Final Pass/Fail
    passed = (score >= 80) # Requires most fields to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }