#!/usr/bin/env python3
"""
Verifier for airline_parametrized_reporting task.

Scoring (100 points total):
1. Setup & Installation (10 pts): nycflights13 installed.
2. RMarkdown Template (20 pts):
   - Exists and created during task (10 pts)
   - Contains 'params' definition (10 pts)
3. Automation Script (20 pts):
   - Exists and created during task (10 pts)
   - Calls 'render' function (10 pts)
4. Output Generation (30 pts):
   - UA Report exists and created during task (10 pts)
   - DL Report exists and created during task (10 pts)
   - Reports are distinct (not copies) (10 pts)
5. Content Accuracy (20 pts):
   - UA Report contains "United Air Lines" (10 pts)
   - DL Report contains "Delta Air Lines" (10 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_airline_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # 1. Setup (10 pts)
    if result.get("nycflights13_installed", False):
        score += 10
        feedback_parts.append("Package nycflights13 installed (+10)")
    else:
        feedback_parts.append("Package nycflights13 NOT installed (0)")

    # 2. RMarkdown Template (20 pts)
    if result.get("template_status") == "new":
        score += 10
        feedback_parts.append("Template Rmd created (+10)")
        if result.get("rmd_has_params", False):
            score += 10
            feedback_parts.append("Template uses params (+10)")
        else:
            feedback_parts.append("Template missing YAML params (0)")
    else:
        feedback_parts.append("Template Rmd missing or old (0)")

    # 3. Automation Script (20 pts)
    if result.get("script_status") == "new":
        score += 10
        feedback_parts.append("Automation script created (+10)")
        if result.get("script_calls_render", False):
            score += 10
            feedback_parts.append("Script calls render() (+10)")
        else:
            feedback_parts.append("Script does not appear to call render() (0)")
    else:
        feedback_parts.append("Automation script missing or old (0)")

    # 4. Output Generation (30 pts)
    # UA Report
    if result.get("ua_report_status") == "new":
        score += 10
        feedback_parts.append("UA Report created (+10)")
    else:
        feedback_parts.append("UA Report missing (0)")
    
    # DL Report
    if result.get("dl_report_status") == "new":
        score += 10
        feedback_parts.append("DL Report created (+10)")
    else:
        feedback_parts.append("DL Report missing (0)")
    
    # Distinctness
    if result.get("reports_are_distinct", False):
        score += 10
        feedback_parts.append("Reports are distinct/generated correctly (+10)")
    elif result.get("ua_report_status") == "new" and result.get("dl_report_status") == "new":
        feedback_parts.append("Reports are identical copies! (Anti-gaming check) (0)")

    # 5. Content Accuracy (20 pts)
    if result.get("ua_report_valid_content", False):
        score += 10
        feedback_parts.append("UA content verified (+10)")
    else:
        feedback_parts.append("UA content validation failed (missing airline name?) (0)")
        
    if result.get("dl_report_valid_content", False):
        score += 10
        feedback_parts.append("DL content verified (+10)")
    else:
        feedback_parts.append("DL content validation failed (missing airline name?) (0)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }