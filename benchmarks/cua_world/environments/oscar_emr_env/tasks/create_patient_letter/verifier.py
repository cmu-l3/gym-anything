#!/usr/bin/env python3
"""
Verifier for create_patient_letter task.
Verifies that a letter was created in Oscar EMR with specific content requirements.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_patient_letter(traj, env_info, task_info):
    """
    Verify the patient letter creation.
    
    Criteria:
    1. Letter exists in database for correct patient (40 pts)
    2. Subject contains expected keywords (20 pts)
    3. Body contains medical condition 'back pain' (20 pts)
    4. Body contains duration '6 months' (10 pts)
    5. Letter created during task session (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    subject_keywords = metadata.get('subject_keywords', ["Cancellation", "Membership"])
    body_keywords = metadata.get('body_keywords', ["back pain", "6 months", "six months"])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Criterion 1: Letter Found
    if result.get('letter_found', False):
        score += 40
        feedback_parts.append("Letter record created")
    else:
        return {"passed": False, "score": 0, "feedback": "No letter record found for patient Maria Santos"}

    # Content Analysis
    subject = result.get('letter_subject', '').lower()
    body = result.get('letter_body', '').lower()
    
    # Criterion 2: Subject Match (20 pts)
    # Flexible check: at least one of the keywords
    subj_matches = [kw for kw in subject_keywords if kw.lower() in subject]
    if subj_matches:
        score += 20
        feedback_parts.append(f"Subject correct (matched '{subj_matches[0]}')")
    else:
        feedback_parts.append(f"Subject missing keywords (Expected: {subject_keywords}, Got: '{subject}')")

    # Criterion 3: Condition Mentioned (20 pts)
    if "back pain" in body:
        score += 20
        feedback_parts.append("Condition 'back pain' verified")
    else:
        feedback_parts.append("Body missing 'back pain'")

    # Criterion 4: Duration Mentioned (10 pts)
    if "6 months" in body or "six months" in body:
        score += 10
        feedback_parts.append("Duration '6 months' verified")
    else:
        feedback_parts.append("Body missing '6 months' duration")

    # Criterion 5: Anti-gaming / New Record check (10 pts)
    # Check if count increased or if we can rely on setup clearing data
    initial = result.get('initial_count', 0)
    current = result.get('current_count', 0)
    if current > initial:
        score += 10
        feedback_parts.append("New record confirmed")
    else:
        feedback_parts.append("Record count did not increase (rewrote existing?)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }