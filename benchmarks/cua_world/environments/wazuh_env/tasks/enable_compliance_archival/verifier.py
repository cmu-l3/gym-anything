#!/usr/bin/env python3
"""
Verifier for enable_compliance_archival task.

Criteria:
1. Wazuh Manager ossec.conf has <logall_json>yes</logall_json> (25 pts)
2. Wazuh Manager ossec.conf has <localfile> for /var/log/legacy_fin_app.log (25 pts)
3. Manager is running (10 pts)
4. The specific test event was found in the archives.json inside the container (20 pts)
5. The agent extracted the event to /home/ga/archive_proof.json (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_compliance_archival(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # 1. Check Logall Configuration (25 pts)
    if result.get("logall_json_enabled", False):
        score += 25
        feedback.append("Global JSON archival enabled.")
    else:
        feedback.append("Failed: <logall_json> is not set to 'yes' in ossec.conf.")

    # 2. Check Localfile Configuration (25 pts)
    if result.get("localfile_configured", False):
        score += 25
        feedback.append("Custom log file monitoring configured.")
    else:
        feedback.append("Failed: <localfile> block for legacy_fin_app.log not found.")

    # 3. Check Manager Running (10 pts)
    if result.get("manager_running", False):
        score += 10
        feedback.append("Wazuh manager is running.")
    else:
        feedback.append("Failed: Wazuh manager service is not running.")

    # 4. Check Event in Archive (20 pts)
    # This proves the pipeline works: config matches, restart happened, file created, log collected.
    if result.get("event_found_in_archive", False):
        score += 20
        feedback.append("Test event successfully archived by Wazuh.")
    else:
        feedback.append("Failed: Test event not found in /var/ossec/logs/archives/archives.json. Did you create the log entry and restart?")

    # 5. Check Proof File (20 pts)
    # This proves the agent verified their own work.
    if result.get("proof_valid", False):
        score += 20
        feedback.append("Proof file extracted correctly.")
    elif result.get("proof_file_exists", False):
        score += 10
        feedback.append("Proof file exists but does not contain the correct token.")
    else:
        feedback.append("Failed: Proof file /home/ga/archive_proof.json not found.")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }