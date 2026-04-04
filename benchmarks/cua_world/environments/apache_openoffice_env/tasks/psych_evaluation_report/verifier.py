#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_psych_report(traj, env_info, task_info):
    """
    Verifies the Psychological Evaluation Report task.
    
    Criteria:
    1. File creation (valid ODT).
    2. "CONFIDENTIAL" text in Header (styles.xml preferred).
    3. Table existence for scores.
    4. Data accuracy (WISC-V scores).
    5. Diagnosis code presence.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Validity (10 pts)
    if result.get("file_exists") and result.get("file_size", 0) > 1000:
        score += 10
        feedback.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found or empty."}

    # 2. Confidential Header (25 pts)
    # Full points if in styles.xml (actual header), partial if in body
    if result.get("has_confidential_header"):
        if "styles.xml" in result.get("header_location", ""):
            score += 25
            feedback.append("Confidential header correctly applied.")
        else:
            score += 10
            feedback.append("Confidential text found, but appears to be in body text rather than page header.")
    else:
        feedback.append("Missing 'CONFIDENTIAL' header.")

    # 3. Table Structure (20 pts)
    if result.get("table_count", 0) >= 1:
        score += 20
        feedback.append("Score table present.")
    else:
        feedback.append("No table found for scores.")

    # 4. Score Data Accuracy (25 pts)
    found_scores = result.get("scores_found", [])
    # 5 scores expected: 112, 98, 105, 88, 85
    # 5 pts per score
    score += len(found_scores) * 5
    if len(found_scores) == 5:
        feedback.append("All WISC-V scores transcribed correctly.")
    else:
        feedback.append(f"Found {len(found_scores)}/5 scores. Missing some data.")

    # 5. Diagnosis & Patient Info (20 pts)
    if result.get("diagnosis_code_found"):
        score += 10
        feedback.append("DSM-5 Diagnosis code (314.01) found.")
    else:
        feedback.append("Diagnosis code missing.")

    if result.get("patient_name_found"):
        score += 10
        feedback.append("Patient name found.")
    else:
        feedback.append("Patient name missing.")

    # Final Pass Check
    # Must have file, header text (anywhere), table, and at least 3 correct scores
    passed = (result.get("file_exists") and 
              result.get("has_confidential_header") and 
              result.get("table_count", 0) >= 1 and 
              len(found_scores) >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }