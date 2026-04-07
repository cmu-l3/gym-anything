#!/usr/bin/env python3
"""
Verifier for monitor_config_diffs task.
Checks:
1. ossec.conf contains the correct FIM configuration.
2. Target file has been modified.
3. An alert was generated with 'syscheck.diff' data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_monitor_config_diffs(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Configuration (30 pts)
    config_snippet = result.get('config_snippet', '')
    target_file = "/var/ossec/etc/critical_app.conf"
    
    if target_file in config_snippet:
        score += 10
        feedback.append("File path found in ossec.conf")
        
        if 'report_changes="yes"' in config_snippet:
            score += 15
            feedback.append("report_changes enabled")
        else:
            feedback.append("report_changes NOT enabled")
            
        if 'realtime="yes"' in config_snippet:
            score += 5
            feedback.append("realtime enabled")
    else:
        feedback.append("File path NOT found in ossec.conf")

    # 2. Verify File Modification (10 pts)
    file_content = result.get('file_content', '')
    # Initial content was "debug_mode=false"
    if "debug_mode=false" not in file_content and "debug_mode=true" in file_content:
         score += 10
         feedback.append("File content modified correctly")
    elif file_content != "not_found" and "debug_mode=false" not in file_content:
         score += 10
         feedback.append("File content modified")
    else:
         feedback.append("File content appears unchanged or missing")

    # 3. Verify Alerts (60 pts)
    alert_analysis = result.get('alert_analysis', {})
    
    if alert_analysis.get('alert_found'):
        score += 30
        feedback.append("FIM alert generated")
        
        if alert_analysis.get('diff_found'):
            score += 30
            feedback.append("Content diff captured in alert")
        else:
            feedback.append("Alert found but NO diff content (did you enable report_changes?)")
    else:
        feedback.append("No FIM alert found for target file")

    # Pass logic
    # Must have alert with diff (critical) + config correct
    passed = (score >= 80) and alert_analysis.get('diff_found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }