#!/usr/bin/env python3
"""
Verifier for verify_evidence_chain_of_custody task.
Checks if the agent correctly identified the file integrity status.
"""

import json
import base64
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_evidence_audit(traj, env_info, task_info):
    """
    Verify the evidence audit report.
    
    Scoring:
    - Report exists and created during task: 20 pts
    - Report contains correct Case Number: 10 pts
    - Report contains correct Recorded Hash: 20 pts
    - Report contains correct Current Hash: 10 pts
    - Report contains correct Status (INTACT/COMPROMISED): 40 pts
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function missing"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    report_exists = result.get('report_exists', False)
    created_during = result.get('file_created_during_task', False)
    ground_truth = result.get('ground_truth', {})
    
    # Ground Truth Values
    gt_status = ground_truth.get('status', 'UNKNOWN')
    gt_recorded = ground_truth.get('recorded_hash', '')
    gt_actual = ground_truth.get('actual_hash', '')
    gt_case = ground_truth.get('case_number', '')

    score = 0
    feedback = []

    # Check 1: File Existence (20 pts)
    if report_exists and created_during:
        score += 20
        feedback.append("Report file created successfully")
        
        # Parse Report Content
        try:
            content_b64 = result.get('report_content_base64', '')
            content = base64.b64decode(content_b64).decode('utf-8')
        except:
            content = ""
            feedback.append("Failed to decode report content")
            
        # Helper regex extraction
        def extract_val(pattern, text):
            m = re.search(pattern, text, re.IGNORECASE)
            return m.group(1).strip() if m else None

        # Check 2: Case Number (10 pts)
        rep_case = extract_val(r"Case Number:\s*(.*)", content)
        if rep_case and gt_case in rep_case:
            score += 10
            feedback.append(f"Correct Case Number: {rep_case}")
        else:
            feedback.append(f"Incorrect Case Number (Expected {gt_case}, Found {rep_case})")

        # Check 3: Recorded Hash (20 pts)
        # Allow partial match (first 10 chars) to be lenient on copy-paste errors, 
        # but full match is preferred. Using strict check for "Forensics".
        rep_rec_hash = extract_val(r"Recorded Hash:\s*([a-fA-F0-9]{64})", content)
        if rep_rec_hash and rep_rec_hash.lower() == gt_recorded.lower():
            score += 20
            feedback.append("Correct Recorded Hash identified")
        else:
            feedback.append(f"Incorrect Recorded Hash (Expected {gt_recorded[:8]}...)")

        # Check 4: Current Hash (10 pts)
        rep_cur_hash = extract_val(r"Current Hash:\s*([a-fA-F0-9]{64})", content)
        if rep_cur_hash and rep_cur_hash.lower() == gt_actual.lower():
            score += 10
            feedback.append("Correct Current Hash calculated")
        else:
            feedback.append(f"Incorrect Current Hash (Expected {gt_actual[:8]}...)")

        # Check 5: Status Determination (40 pts)
        # This is the critical thinking part.
        rep_status = extract_val(r"Status:\s*(.*)", content)
        if rep_status and gt_status.upper() in rep_status.upper():
            score += 40
            feedback.append(f"Correct Status Determination: {gt_status}")
        else:
            feedback.append(f"WRONG STATUS DETERMINATION. Expected {gt_status}, got {rep_status}")

    else:
        feedback.append("Report file not found or not created during task")

    # Final Pass Check
    # Must have the correct status and at least 70 points
    passed = (score >= 70) and ("Correct Status Determination" in "".join(feedback))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }