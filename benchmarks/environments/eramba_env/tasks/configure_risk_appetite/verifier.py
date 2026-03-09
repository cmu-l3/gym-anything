#!/usr/bin/env python3
"""
Verifier for configure_risk_appetite task.
Verifies that risk appetite was updated to 2 (Low) for all three risk domains.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_risk_appetite(traj, env_info, task_info):
    """
    Verifies that the agent configured the risk appetite settings correctly.
    
    Criteria:
    1. Enterprise Risks appetite = 2 (25 pts)
    2. Third Party Risks appetite = 2 (25 pts)
    3. Business Continuity appetite = 2 (25 pts)
    4. Methods preserved (10 pts)
    5. Calc methods preserved (5 pts)
    6. Modified timestamp > task start (5 pts)
    7. App running (5 pts)
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Target values
    TARGET_APPETITE = "2"
    TARGET_METHOD = "0"
    TARGET_CALC = "eramba"

    # 1. Check Enterprise Risks (Risks)
    risks = result.get("risks", {})
    if str(risks.get("appetite")) == TARGET_APPETITE:
        score += 25
        feedback.append("Enterprise Risks updated correctly.")
    else:
        feedback.append(f"Enterprise Risks appetite is '{risks.get('appetite')}' (expected {TARGET_APPETITE}).")

    # 2. Check Third Party Risks
    tpr = result.get("third_party", {})
    if str(tpr.get("appetite")) == TARGET_APPETITE:
        score += 25
        feedback.append("Third Party Risks updated correctly.")
    else:
        feedback.append(f"Third Party Risks appetite is '{tpr.get('appetite')}' (expected {TARGET_APPETITE}).")

    # 3. Check Business Continuity
    bc = result.get("business_continuity", {})
    if str(bc.get("appetite")) == TARGET_APPETITE:
        score += 25
        feedback.append("Business Continuity Risks updated correctly.")
    else:
        feedback.append(f"Business Continuity appetite is '{bc.get('appetite')}' (expected {TARGET_APPETITE}).")

    # 4. Check Methods (All must be 0)
    methods_ok = (str(risks.get("method")) == TARGET_METHOD and 
                  str(tpr.get("method")) == TARGET_METHOD and 
                  str(bc.get("method")) == TARGET_METHOD)
    if methods_ok:
        score += 10
        feedback.append("Risk appetite methods preserved.")
    else:
        feedback.append("One or more risk appetite methods were incorrectly changed.")

    # 5. Check Calc Methods (All must be 'eramba')
    calcs_ok = (str(risks.get("calc_method")) == TARGET_CALC and 
                str(tpr.get("calc_method")) == TARGET_CALC and 
                str(bc.get("calc_method")) == TARGET_CALC)
    if calcs_ok:
        score += 5
        feedback.append("Risk calculation methods preserved.")
    else:
        feedback.append("One or more risk calculation methods were incorrectly changed.")

    # 6. Check Anti-Gaming (Timestamps)
    # Check if at least one record was modified during the task
    modified = (risks.get("modified_during_task") or 
                tpr.get("modified_during_task") or 
                bc.get("modified_during_task"))
    if modified:
        score += 5
        feedback.append("DB modification detected during task.")
    else:
        feedback.append("No DB modifications detected during task window (Possible gaming or no action).")
    
    # 7. Check App Running
    if result.get("app_running"):
        score += 5
        feedback.append("Browser was running.")

    # Determine pass/fail
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }