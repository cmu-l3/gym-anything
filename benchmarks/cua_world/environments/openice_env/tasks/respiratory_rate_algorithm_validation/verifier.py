#!/usr/bin/env python3
"""
Verifier for respiratory_rate_algorithm_validation task.

Scoring Criteria (100 points total):
1. Capnograph Created (30 pts): Log/Window evidence of correct device type.
2. App Launched (30 pts): Evidence of Respiratory Rate Calculator app.
3. Report Existence (10 pts): File exists and written during task.
4. Report Content (30 pts): Contains numbers and validation keywords.

Anti-gaming:
- Checks timestamps to ensure report was created during task.
- Penalizes if wrong device type (Multiparameter) is detected if Capnograph is missing.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_respiratory_rate_validation(traj, env_info, task_info):
    # Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    # Extract data
    task_start = result.get('task_start_timestamp', 0)
    openice_running = result.get('openice_running', False)
    capnograph_created = result.get('capnograph_created', False)
    multiparam_created = result.get('multiparam_created', False)
    app_launched = result.get('app_launched', False)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_has_numbers = result.get('report_has_numbers', False)
    report_has_keywords = result.get('report_has_keywords', False)
    report_size = result.get('report_size', 0)

    # Criterion 1: OpenICE Running (Critical Gate)
    if not openice_running:
        return {"passed": False, "score": 0, "feedback": "FAIL: OpenICE application is not running."}

    # Criterion 2: Device Creation (30 pts)
    if capnograph_created:
        score += 30
        feedback_parts.append("Correct device (Capnograph) created.")
    elif multiparam_created:
        score += 5
        feedback_parts.append("Wrong device type created (Multiparameter instead of Capnograph). Partial credit.")
    else:
        feedback_parts.append("No Capnograph device detected.")

    # Criterion 3: App Launch (30 pts)
    if app_launched:
        score += 30
        feedback_parts.append("Respiratory Rate Calculator app launched.")
    else:
        # Check window increase as fallback evidence of some app launch
        if result.get('window_increase', 0) >= 2:
             score += 10
             feedback_parts.append("App likely launched (window count increased), but specific app title not confirmed.")
        else:
             feedback_parts.append("Respiratory Rate Calculator app not detected.")

    # Criterion 4: Report Existence (10 pts)
    # Check if file modified *after* task start
    is_fresh_report = report_exists and (int(report_mtime) > int(task_start))
    
    if is_fresh_report and report_size > 0:
        score += 10
        feedback_parts.append("Validation report created.")
    elif report_exists:
        score += 5
        feedback_parts.append("Report exists but timestamp is ambiguous.")
    else:
        feedback_parts.append("No validation report found.")

    # Criterion 5: Report Content (30 pts)
    content_score = 0
    if is_fresh_report or report_exists:
        if report_has_numbers:
            content_score += 15
            feedback_parts.append("Report contains numerical data.")
        else:
            feedback_parts.append("Report missing numerical values.")
            
        if report_has_keywords:
            content_score += 15
            feedback_parts.append("Report contains validation keywords.")
        else:
            feedback_parts.append("Report missing comparison/conclusion.")
    
    score += content_score

    # Final Pass Determination
    # Must have created correct device OR launched app, AND created a valid report
    passed = (score >= 70) and is_fresh_report

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }