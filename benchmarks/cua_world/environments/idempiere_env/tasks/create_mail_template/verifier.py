#!/usr/bin/env python3
"""
Verifier for create_mail_template task.

Checks:
1. Database record exists for 'Vendor Order Inquiry'.
2. Subject line matches exactly (critical for automated emails).
3. Body text contains required fragments and variables.
4. Record was created after task start time (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_mail_template(traj, env_info, task_info):
    """
    Verify the creation of the Mail Template in iDempiere.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', 'Status Update Request - Order @DocumentNo@')
    required_fragments = metadata.get('required_body_fragments', [])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Result
    db_record = result.get('db_record')
    task_start = result.get('task_start_time', 0)
    
    score = 0
    feedback = []
    
    # 3. Verification Logic
    
    # Criterion 1: Record Existence (30 pts)
    if not db_record:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Mail Template 'Vendor Order Inquiry' not found in database."
        }
    
    score += 30
    feedback.append("Mail Template record found.")
    
    # Criterion 2: Anti-Gaming / Timestamp (10 pts)
    created_epoch = db_record.get('created_epoch', 0)
    if float(created_epoch) > float(task_start):
        score += 10
        feedback.append("Record created during task session.")
    else:
        feedback.append("Warning: Record appears to be old (created before task start).")

    # Criterion 3: Subject Line (20 pts)
    # We strip whitespace to be slightly lenient on trailing spaces
    actual_subject = db_record.get('mailheader', '').strip()
    if actual_subject == expected_subject.strip():
        score += 20
        feedback.append("Subject line is correct.")
    else:
        feedback.append(f"Subject mismatch. Expected: '{expected_subject}', Got: '{actual_subject}'")

    # Criterion 4: Body Content & Variables (40 pts total)
    actual_body = db_record.get('mailtext', '')
    
    # Check for variables specifically (20 pts)
    vars_present = 0
    if "@DocumentNo@" in actual_body:
        vars_present += 10
    else:
        feedback.append("Missing variable @DocumentNo@ in body.")
        
    if "@DateOrdered@" in actual_body:
        vars_present += 10
    else:
        feedback.append("Missing variable @DateOrdered@ in body.")
    
    score += vars_present
    if vars_present == 20:
        feedback.append("Context variables found.")

    # Check for general text content (20 pts)
    # We check if specific key phrases exist
    fragments_found = 0
    missed_fragments = []
    
    for frag in required_fragments:
        if frag in actual_body:
            fragments_found += 1
        else:
            missed_fragments.append(frag)
            
    if len(missed_fragments) == 0:
        score += 20
        feedback.append("Body text content matches requirements.")
    else:
        # Partial credit for body text
        partial_score = int(20 * (fragments_found / len(required_fragments)))
        score += partial_score
        feedback.append(f"Body text missing some parts: {', '.join(missed_fragments[:2])}...")

    # Final Check
    passed = score >= 70 and db_record is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }