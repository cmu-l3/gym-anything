#!/usr/bin/env python3
"""
Verifier for develop_realtime_pick_monitor task.
"""

import json
import os
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_develop_realtime_pick_monitor(traj, env_info, task_info):
    """
    Verifies the script was written and successfully caught the dynamically injected pick.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely extract verification data from the exported JSON
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
    feedback = []

    # Unpack JSON contents
    script_exists = result.get('script_exists', False)
    log_exists = result.get('log_exists', False)
    target_id = result.get('target_id', '')
    script_b64 = result.get('script_b64', '')
    log_b64 = result.get('log_b64', '')
    task_start = result.get('task_start', 0)
    log_mtime = result.get('log_mtime', 0)

    # Decode base64 payloads to strings
    script_content = ""
    if script_b64:
        try:
            script_content = base64.b64decode(script_b64).decode('utf-8', errors='ignore')
        except Exception:
            pass

    log_content = ""
    if log_b64:
        try:
            log_content = base64.b64decode(log_b64).decode('utf-8', errors='ignore')
        except Exception:
            pass

    # Criterion 1: Evaluate Python script structure & existence (40 points max)
    if script_exists:
        score += 10
        feedback.append("pick_monitor.py created (10/10).")

        # Anti-gaming check: Ensure the script didn't just read the XML file off disk
        if "sample_pick.xml" in script_content:
            feedback.append("FAIL: Script contains reference to 'sample_pick.xml'. It must receive messages via the SeisComP message bus API, not bypass it by reading the file directly.")
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

        # Evaluate architecture logic
        has_seiscomp = "seiscomp" in script_content
        has_app = "Application" in script_content or "Client" in script_content

        if has_seiscomp and has_app:
            score += 30
            feedback.append("Script correctly imports SeisComP and implements Application/Client architecture (30/30).")
        elif has_seiscomp:
            score += 15
            feedback.append("Script imports SeisComP but lacks clear Application/Client class inheritance (15/30).")
        else:
            feedback.append("Script does not appear to use the expected SeisComP API (0/30).")
    else:
        feedback.append("pick_monitor.py not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 2: Evaluate Log file existence (10 points max)
    if log_exists:
        score += 10
        feedback.append("pick_log.txt created (10/10).")

        # Basic anti-gaming: Ensure it was made/modified after the task started
        if 0 < log_mtime < task_start:
            feedback.append("FAIL: Log file was created/modified before task start.")
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

        # Criterion 3: Ensure log file accurately captured the DYNAMIC pick ID (50 points max)
        if target_id and target_id in log_content:
            score += 50
            feedback.append(f"SUCCESS: Log file captured the dynamically injected Pick ID via the message bus ({target_id}) (50/50).")
        else:
            feedback.append(f"FAIL: Log file does not contain the target Pick ID. Log output snippet: {log_content[:100]!r}")
    else:
        feedback.append("pick_log.txt not found. The script likely did not run or failed to intercept the pick message (0/60).")

    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }