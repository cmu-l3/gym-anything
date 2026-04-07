#!/usr/bin/env python3
"""
Verifier for export_patient_ccda task.
Checks if the agent successfully exported the CCDA XML for the correct patient.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_patient_ccda(traj, env_info, task_info):
    """
    Verify that the CCDA XML file was exported correctly.
    
    Criteria:
    1. File exists at /home/ga/Documents/maria_rodriguez_ccda.xml (20 pts)
    2. File was created during the task window (20 pts)
    3. File is valid XML (20 pts)
    4. File contains correct patient name (40 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence
    if result.get("file_exists", False):
        score += 20
        feedback.append("File found at correct location.")
    else:
        feedback.append("File NOT found at /home/ga/Documents/maria_rodriguez_ccda.xml.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Anti-gaming / Timestamp
    if result.get("file_created_during_task", False):
        score += 20
        feedback.append("File created during task session.")
    else:
        feedback.append("File timestamp indicates it was not created during this task.")
        # If file existed before, they didn't do the task
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. Valid XML
    if result.get("is_valid_xml", False):
        score += 20
        feedback.append("File is valid XML.")
    else:
        feedback.append(f"File is NOT valid XML. Error: {result.get('xml_error', 'unknown')}")

    # 4. Content Check
    if result.get("contains_patient_name", False):
        score += 40
        feedback.append("XML contains correct patient data (Maria Rodriguez).")
    else:
        feedback.append("XML does not appear to contain the correct patient name.")

    # Pass threshold
    passed = score >= 80  # Requires file exists + timestamp + (xml valid AND content correct) roughly
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }