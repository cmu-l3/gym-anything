#!/usr/bin/env python3
"""
Verifier for record_patient_amendment task.

Criteria:
1. Amendment record exists in DB for correct PID (25 pts)
2. Description contains required keywords (25 pts)
3. Status is 'Accepted' (15 pts)
4. Date is '2025-01-15' (15 pts)
5. Anti-gaming: Record count increased by exactly 1 (10 pts)
6. VLM: Trajectory shows interaction with Amendment UI (10 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(images, prompt): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_patient_amendment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_date = metadata.get('expected_date', '2025-01-15')
    expected_status = metadata.get('expected_status', 'Accepted')
    required_keywords = metadata.get('required_keywords', ['allergy', 'Amoxicillin'])

    # Get result from container
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

    score = 0
    feedback = []
    
    # 1. Database Verification (Primary)
    record_found = result.get("record_found", False)
    count_diff = result.get("count_diff", 0)
    
    if not record_found:
        return {"passed": False, "score": 0, "feedback": "No amendment record found in database for this patient."}

    # Criterion 1: Record exists
    score += 25
    feedback.append("Amendment record found.")

    # Criterion 2: Description Content
    rec_desc = result.get("record_desc", "")
    keywords_found = [k for k in required_keywords if k.lower() in rec_desc.lower()]
    if len(keywords_found) >= len(required_keywords) - 1: # Allow missing 1 keyword
        score += 25
        feedback.append("Description contains required details.")
    else:
        feedback.append(f"Description missing keywords. Found: {keywords_found}, Expected: {required_keywords}")

    # Criterion 3: Status
    rec_status = result.get("record_status", "")
    if rec_status.lower() == expected_status.lower():
        score += 15
        feedback.append(f"Status is '{rec_status}'.")
    else:
        feedback.append(f"Incorrect status: '{rec_status}' (Expected: {expected_status})")

    # Criterion 4: Date
    rec_date = result.get("record_date", "")
    # Handle potential formatting differences (e.g., time included)
    if expected_date in rec_date:
        score += 15
        feedback.append(f"Date is correct ({expected_date}).")
    else:
        feedback.append(f"Incorrect date: '{rec_date}' (Expected: {expected_date})")

    # Criterion 5: Anti-Gaming (Count Diff)
    if count_diff == 1:
        score += 10
        feedback.append("Exactly one new record created.")
    elif count_diff > 1:
        score += 5
        feedback.append("Multiple records created (duplicates?).")
    else:
        feedback.append("No net increase in record count (overwrote existing?).")

    # 2. VLM Verification (Secondary)
    # Check if agent actually navigated the UI
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Analyze these screenshots of an Electronic Health Record (EHR) system. "
            "Determine if the user: \n"
            "1. Opened a patient chart (look for 'Brandie Sammet').\n"
            "2. Navigated to an 'Amendments' or 'Medical Record' section.\n"
            "3. Filled out a text form relating to allergies.\n"
            "Reply with JSON: {\"chart_opened\": bool, \"amendment_form_seen\": bool, \"confidence\": 0-1}"
        )
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('chart_opened') and parsed.get('amendment_form_seen'):
                score += 10
                feedback.append("VLM confirmed UI workflow.")
            else:
                feedback.append("VLM could not confirm full UI workflow.")
        else:
            # Fallback if VLM fails: give points if DB record is perfect
            if score >= 80:
                score += 10
                feedback.append("VLM skipped (high confidence DB match).")

    # Final Pass/Fail
    passed = score >= 60 and record_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }