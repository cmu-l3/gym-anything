#!/usr/bin/env python3
"""Verifier for Troubleshoot Split Study task"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_troubleshoot_split_study(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    report_exists = result.get('report_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    report_content = result.get('report_content', '')
    expected_filename = result.get('expected_filename', '')
    expected_patient_id = result.get('expected_patient_id', '')
    
    if not expected_filename or not expected_patient_id:
        return {"passed": False, "score": 0, "feedback": "Ground truth missing in result (task setup failed)"}

    # CRITERION 1: File Exists & Was Actually Authored During the Run
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists")
        if file_created_during_task:
            feedback_parts.append("File created during active task")
        else:
            feedback_parts.append("Warning: File existed prior to task execution (possible gaming)")
    else:
        feedback_parts.append("Report file NOT found")
        # Exit early if the fundamental file requirement is missing
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Convert pipes (inserted in export script) back to newlines for parsing
    content = report_content.replace('|', '\n')
    
    filename_match = re.search(r'Filename:\s*([^\n]+)', content, re.IGNORECASE)
    patient_id_match = re.search(r'PatientID:\s*([^\n]+)', content, re.IGNORECASE)
    
    parsed_filename = filename_match.group(1).strip() if filename_match else ""
    parsed_patient_id = patient_id_match.group(1).strip() if patient_id_match else ""
    
    # CRITERION 2: File Formatting Follows Specification
    if parsed_filename or parsed_patient_id:
        score += 10
        feedback_parts.append("Report format correct")
    else:
        feedback_parts.append("Incorrect report format (keys missing or malformed)")
        
    # CRITERION 3: Accurately Captured Corrupted Filename
    if parsed_filename.lower() == expected_filename.lower():
        score += 40
        feedback_parts.append("Correct filename identified")
    elif parsed_filename:
        feedback_parts.append(f"Incorrect filename: expected {expected_filename}, got {parsed_filename}")
        
    # CRITERION 4: Accurately Extracted Random Incorrect ID
    if parsed_patient_id.lower() == expected_patient_id.lower():
        score += 40
        feedback_parts.append("Correct PatientID identified")
    elif parsed_patient_id:
        feedback_parts.append(f"Incorrect PatientID: expected {expected_patient_id}, got {parsed_patient_id}")
        
    # Optional Validation: Validate Trajectory Workflow via VLM if Available
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = """Analyze these trajectory frames from a desktop agent session.
Does the agent actively inspect DICOM files by either:
1. Navigating through a DICOM Viewer interface (e.g. Weasis patient browser or metadata views)
2. Using a terminal to run commands like 'dicom-info' or 'dcmdump' on the DICOM files
Reply strictly in JSON format: {"process_verified": true} or {"process_verified": false}"""
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("process_verified"):
                    feedback_parts.append("VLM verified diagnostic workflow")
    except Exception as e:
        logger.info(f"VLM trajectory verification skipped or failed: {e}")

    # Final tally (Pass requires full accuracy due to the strict QA nature of the test)
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }