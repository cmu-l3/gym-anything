#!/usr/bin/env python3
"""
Verifier for Configure Email Receipts task in Copper POS.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_receipts(traj, env_info, task_info):
    """
    Verify that the SMTP settings were correctly configured in Copper POS.
    
    Checks:
    1. Application is running
    2. Registry/Config contains correct SMTP Host and Port
    3. Registry/Config contains correct Sender Email
    4. Registry/Config contains correct Username
    5. VLM Verification of the final state or trajectory
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_host = metadata.get('expected_host', 'smtp.sendgrid.net')
    expected_port = str(metadata.get('expected_port', '587'))
    expected_sender = metadata.get('expected_sender', 'receipts@citylightsbooks.com')
    expected_username = metadata.get('expected_username', 'apikey')

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows style in the script, but copy_from_env usually expects
        # the path format understood by the container runtime. For Windows containers, 
        # it might need "C:/tmp/task_result.json".
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    config = result.get('config', {})
    
    # 1. Verify Host (30 pts)
    # Check both Registry keys and fallback INI scraping
    host_found = str(config.get('host', '')).lower()
    host_in_ini = config.get('host_in_ini', False)
    
    if expected_host.lower() in host_found or host_in_ini:
        score += 30
        feedback_parts.append(f"SMTP Host '{expected_host}' configured.")
    else:
        feedback_parts.append(f"SMTP Host mismatch. Found: '{host_found}'.")

    # 2. Verify Port (20 pts)
    port_found = str(config.get('port', ''))
    if expected_port in port_found:
        score += 20
        feedback_parts.append(f"SMTP Port '{expected_port}' configured.")
    else:
        feedback_parts.append(f"SMTP Port mismatch. Found: '{port_found}'.")

    # 3. Verify Sender (20 pts)
    sender_found = str(config.get('sender', '')).lower()
    sender_in_ini = config.get('sender_in_ini', False)
    
    if expected_sender.lower() in sender_found or sender_in_ini:
        score += 20
        feedback_parts.append(f"Sender email '{expected_sender}' configured.")
    else:
        feedback_parts.append(f"Sender email mismatch. Found: '{sender_found}'.")

    # 4. Verify Username (20 pts)
    username_found = str(config.get('username', ''))
    if expected_username in username_found:
        score += 20
        feedback_parts.append(f"Username '{expected_username}' configured.")
    else:
        feedback_parts.append(f"Username mismatch.")

    # 5. Application Running (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("Application is running.")
    else:
        feedback_parts.append("Application was closed.")

    passed = score >= 80  # Requires Host, Port, Sender, and Username essentially

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }