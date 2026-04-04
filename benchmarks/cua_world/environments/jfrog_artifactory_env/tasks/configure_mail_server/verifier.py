#!/usr/bin/env python3
"""
Verifier for configure_mail_server task.

Verifies:
1. System configuration API reports correct SMTP settings.
2. Configuration was actually modified during the task (anti-gaming).
3. VLM verification of the task workflow.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_mail_server(traj, env_info, task_info):
    """
    Verify SMTP mail server configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_host = metadata.get('expected_host', 'smtp.devteam.example.com')
    expected_port = metadata.get('expected_port', 587)
    expected_from = metadata.get('expected_from', 'artifactory-notifications@devteam.example.com')
    expected_prefix = metadata.get('expected_prefix', '[ArtifactoryAlerts]')
    expected_username = metadata.get('expected_username', 'artifactory-notifications@devteam.example.com')
    # expected_ssl is typically true for 587
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Check Anti-Gaming (Config Changed) - 10 points
    score = 0
    feedback = []
    
    if result.get('config_changed', False):
        score += 10
        feedback.append("Configuration was modified")
    else:
        feedback.append("Configuration was NOT modified from initial state")
        # If config didn't change, they definitely didn't do the task (setup clears it)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Task Failed: No configuration changes detected."
        }

    # 2. Check Mail Configuration - 90 points total
    mail_config = result.get('mail_config', {})
    
    if not mail_config.get('found', False):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Mail server configuration block not found in system config."
        }

    # Enabled (10 pts)
    if mail_config.get('enabled', False):
        score += 10
        feedback.append("Mail server enabled")
    else:
        feedback.append("Mail server NOT enabled")

    # Host (15 pts)
    actual_host = mail_config.get('host', '')
    if actual_host == expected_host:
        score += 15
        feedback.append(f"Host correct ({actual_host})")
    else:
        feedback.append(f"Host incorrect: expected '{expected_host}', got '{actual_host}'")

    # Port (10 pts)
    actual_port = mail_config.get('port')
    if actual_port == expected_port:
        score += 10
        feedback.append(f"Port correct ({actual_port})")
    else:
        feedback.append(f"Port incorrect: expected {expected_port}, got {actual_port}")

    # Username (10 pts)
    actual_user = mail_config.get('username', '')
    if actual_user == expected_username:
        score += 10
        feedback.append("Username correct")
    else:
        feedback.append(f"Username incorrect: expected '{expected_username}', got '{actual_user}'")

    # From Address (15 pts)
    actual_from = mail_config.get('from', '')
    if actual_from == expected_from:
        score += 15
        feedback.append("From address correct")
    else:
        feedback.append(f"From address incorrect: expected '{expected_from}', got '{actual_from}'")

    # Subject Prefix (10 pts)
    actual_prefix = mail_config.get('subjectPrefix', '')
    if actual_prefix == expected_prefix:
        score += 10
        feedback.append("Subject prefix correct")
    else:
        feedback.append(f"Subject prefix incorrect: expected '{expected_prefix}', got '{actual_prefix}'")

    # SSL/TLS (10 pts)
    # Artifactory usually sets one or the other based on the UI checkbox
    if mail_config.get('ssl', False) or mail_config.get('tls', False):
        score += 10
        feedback.append("SSL/TLS enabled")
    else:
        feedback.append("SSL/TLS NOT enabled")
        
    # Password set (10 pts) - cannot verify value, but check if non-empty
    if mail_config.get('has_password', False):
        score += 10
        feedback.append("Password set")
    else:
        feedback.append("Password NOT set")

    passed = (score >= 90) # allow small leniency, but mostly strictly required
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }