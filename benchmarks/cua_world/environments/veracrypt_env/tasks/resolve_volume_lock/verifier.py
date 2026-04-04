#!/usr/bin/env python3
"""
Verifier for resolve_volume_lock task.

Scoring Criteria:
1. Volume successfully dismounted (40 pts)
2. Incident report file exists (10 pts)
3. Incident report contains correct PID (40 pts)
4. Incident report contains correct process name 'tail' (10 pts)

Anti-gaming:
- Report file must be created during the task window.
- PID matches the specific random PID generated for this session.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_volume_lock(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Volume Dismounted (40 pts)
    if result.get('volume_dismounted', False):
        score += 40
        feedback_parts.append("Volume successfully dismounted")
    else:
        feedback_parts.append("Volume is STILL mounted")

    # Criterion 2: Report Exists & Anti-gaming (10 pts)
    report_exists = result.get('report_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if report_exists and created_during:
        score += 10
        feedback_parts.append("Report created")
    elif report_exists:
        feedback_parts.append("Report exists but has old timestamp (pre-task?)")
    else:
        feedback_parts.append("Incident report missing")

    # Criterion 3: Correct PID (40 pts)
    actual_pid = str(result.get('actual_pid', '')).strip()
    report_content = result.get('report_content', '')
    
    # Robust check: Look for the PID as a discrete word in the text
    if actual_pid and re.search(r'\b' + re.escape(actual_pid) + r'\b', report_content):
        score += 40
        feedback_parts.append(f"Correct PID ({actual_pid}) identified")
    elif actual_pid:
        feedback_parts.append(f"Report does NOT contain correct PID ({actual_pid})")
    else:
        feedback_parts.append("Ground truth PID missing (setup error)")

    # Criterion 4: Process Name (10 pts)
    # The setup script uses 'tail', so we look for that
    if re.search(r'tail', report_content, re.IGNORECASE):
        score += 10
        feedback_parts.append("Process name 'tail' identified")
    else:
        feedback_parts.append("Process command name not found in report")

    # Final Evaluation
    # Pass threshold: 80 (Needs to dismount AND identify PID correctly)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }