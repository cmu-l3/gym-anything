#!/usr/bin/env python3
"""
Verifier for configure_email_alerts task.

Checks:
1. Config file exists and was modified during task.
2. SMTP Server matches expected value.
3. Email matches expected value.
4. Port matches expected value.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_alerts(traj, env_info, task_info):
    """
    Verify that JStock email alert settings were configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_server = metadata.get('expected_smtp_server', 'smtp.gmail.com')
    expected_email = metadata.get('expected_email', 'portfolio.alerts@gmail.com')
    expected_port = metadata.get('expected_smtp_port', '587')

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    settings = result.get('settings_found', {})
    config_found = result.get('config_found', False)
    file_modified = result.get('file_modified_during_task', False)

    # 1. Config File Discovery (Foundation)
    if not config_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No configuration file found containing the SMTP settings. Did you save the settings?"
        }

    # 2. Anti-Gaming: File Modification Time (20 pts)
    if file_modified:
        score += 20
        feedback_parts.append("Settings saved successfully (file modified).")
    else:
        feedback_parts.append("Warning: Config file found but not modified during task (old settings?).")

    # 3. Verify Specific Values
    # SMTP Server (30 pts)
    if settings.get('server', False):
        score += 30
        feedback_parts.append(f"SMTP Server '{expected_server}' configured correctly.")
    else:
        feedback_parts.append(f"SMTP Server mismatch or missing.")

    # Email Address (30 pts)
    if settings.get('email', False):
        score += 30
        feedback_parts.append(f"Email '{expected_email}' configured correctly.")
    else:
        feedback_parts.append(f"Email address mismatch or missing.")

    # Port (20 pts)
    if settings.get('port', False):
        score += 20
        feedback_parts.append(f"Port '{expected_port}' configured correctly.")
    else:
        feedback_parts.append(f"Port mismatch or missing.")

    # Final Evaluation
    passed = (score >= 60) and (settings.get('server', False) and settings.get('email', False))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }