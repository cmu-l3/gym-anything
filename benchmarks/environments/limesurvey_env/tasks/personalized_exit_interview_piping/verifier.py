#!/usr/bin/env python3
"""
Verifier for personalized_exit_interview_piping task.

Criteria:
1. Survey 'Employee Exit Interview 2024' exists (Gate).
2. Question 1 has code 'EMPNAME' and is mandatory.
3. Question 2 has code 'REASON' and at least 4 options.
4. Question 3 contains correct Expression Script piping: '{EMPNAME}' and '{REASON.shown}'.
5. Survey is active.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_personalized_exit_interview_piping(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # Gate: Survey Found
    if not result.get("survey_found", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey 'Employee Exit Interview 2024' not found."
        }
    
    # 1. Active Status (20 pts)
    # LimeSurvey active status is 'Y'
    if result.get("survey_active") == "Y":
        score += 20
        feedback_parts.append("Survey is active [20/20]")
    else:
        feedback_parts.append("Survey is NOT active [0/20]")

    # 2. Q1 Configuration (20 pts)
    # Code must be EMPNAME, Mandatory Y
    q_name_code = result.get("q_name_code", "")
    q_name_mandatory = result.get("q_name_mandatory", "N")
    
    if q_name_code == "EMPNAME":
        score += 10
        feedback_parts.append("Q1 Code 'EMPNAME' correct [10/10]")
    else:
        feedback_parts.append(f"Q1 Code incorrect (expected 'EMPNAME', got '{q_name_code}') [0/10]")

    if q_name_mandatory == "Y":
        score += 10
        feedback_parts.append("Q1 Mandatory correct [10/10]")
    else:
        feedback_parts.append("Q1 Not Mandatory [0/10]")

    # 3. Q2 Configuration (20 pts)
    # Code REASON, Options >= 4
    q_reason_code = result.get("q_reason_code", "")
    q_reason_options = result.get("q_reason_options", 0)

    if q_reason_code == "REASON":
        score += 10
        feedback_parts.append("Q2 Code 'REASON' correct [10/10]")
    else:
        feedback_parts.append(f"Q2 Code incorrect (expected 'REASON', got '{q_reason_code}') [0/10]")
        
    if q_reason_options >= 4:
        score += 10
        feedback_parts.append(f"Q2 has {q_reason_options} options [10/10]")
    else:
        feedback_parts.append(f"Q2 has insufficient options ({q_reason_options} < 4) [0/10]")

    # 4. Piping Syntax (40 pts)
    # Must contain {EMPNAME} and {REASON.shown}
    piping_text = result.get("q_piping_text", "")
    
    has_empname = "{EMPNAME}" in piping_text
    has_reason_shown = "{REASON.shown}" in piping_text
    
    if has_empname:
        score += 20
        feedback_parts.append("Piping '{EMPNAME}' found [20/20]")
    else:
        feedback_parts.append("Piping '{EMPNAME}' missing [0/20]")
        
    if has_reason_shown:
        score += 20
        feedback_parts.append("Piping '{REASON.shown}' found [20/20]")
    elif "{REASON}" in piping_text:
        score += 5
        feedback_parts.append("Piping '{REASON}' found, but missing '.shown' suffix [5/20]")
    else:
        feedback_parts.append("Piping '{REASON.shown}' missing [0/20]")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }